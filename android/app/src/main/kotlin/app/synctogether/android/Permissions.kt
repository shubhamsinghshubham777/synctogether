package app.synctogether.android

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Camera and microphone permission, read and asked for on purpose (the
 * pre-show check, board 94), plus the two settings pages a fix usually lives on.
 * Dart side: lib/av/system_permissions.dart (channel `app.synctogether/permissions`).
 *
 * Nothing here prompts by itself: `status` only reads, and `request` is the one
 * call that shows the system dialog, made because a person just tapped a row.
 *
 * Android never says "denied for good" - it just stops showing the dialog. So a
 * refusal is `denied` (the system will still ask) until it has been asked and
 * is not asking again, which is `blocked`: only Settings can change that.
 */
object Permissions {
  private const val PREFS = "permissions"
  private const val REQUEST = 4727

  private var pending: MethodChannel.Result? = null
  private var pendingKind: String? = null

  private fun permissionFor(kind: String?): String? = when (kind) {
    "camera" -> Manifest.permission.CAMERA
    "mic" -> Manifest.permission.RECORD_AUDIO
    else -> null
  }

  fun register(messenger: BinaryMessenger, activity: Activity) {
    MethodChannel(messenger, "app.synctogether/permissions").setMethodCallHandler { call, result ->
      when (call.method) {
        "status" -> result.success(status(activity, call.argument<String>("kind")))
        "request" -> request(activity, call.argument<String>("kind"), result)
        "openAppSettings" -> {
          activity.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
              .setData(Uri.fromParts("package", activity.packageName, null)),
          )
          result.success(null)
        }
        "networkInfo" -> result.success(networkInfo(activity))
        "openNetworkSettings" -> {
          val opened = try {
            activity.startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
            true
          } catch (_: Exception) {
            false
          }
          result.success(opened)
        }
        else -> result.notImplemented()
      }
    }
  }

  /**
   * What the connection is, for the "you're on mobile data" and "Data Saver is
   * on" notes: `transport` is wifi, cellular, other or none; `saver` is Data
   * Saver restricting background traffic.
   */
  private fun networkInfo(context: Context): Map<String, Any> {
    val manager = context.getSystemService(ConnectivityManager::class.java)
      ?: return mapOf("transport" to "other", "saver" to false)
    val caps = manager.getNetworkCapabilities(manager.activeNetwork)
    val transport = when {
      caps == null -> "none"
      caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
        caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "wifi"
      caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
      else -> "other"
    }
    return mapOf(
      "transport" to transport,
      "saver" to (manager.restrictBackgroundStatus == ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED),
    )
  }

  private fun asked(context: Context, kind: String) =
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("asked_$kind", false)

  private fun status(activity: Activity, kind: String?): String {
    val permission = permissionFor(kind) ?: return "unknown"
    if (activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return "granted"
    if (activity.shouldShowRequestPermissionRationale(permission)) return "denied"
    return if (asked(activity, kind!!)) "blocked" else "notDetermined"
  }

  private fun request(activity: Activity, kind: String?, result: MethodChannel.Result) {
    val permission = permissionFor(kind) ?: return result.success("unknown")
    if (activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
      return result.success("granted")
    }
    // A second request while the dialog is up replaces the first.
    pending?.success(status(activity, pendingKind))
    pending = result
    pendingKind = kind
    activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("asked_$kind", true).apply()
    activity.requestPermissions(arrayOf(permission), REQUEST)
  }

  /** From the activity's onRequestPermissionsResult; true when it was ours. */
  fun onPermissionResult(activity: Activity, requestCode: Int): Boolean {
    if (requestCode != REQUEST) return false
    pending?.success(status(activity, pendingKind))
    pending = null
    pendingKind = null
    return true
  }
}
