package app.synctogether.android

import android.app.AppOpsManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.util.Rational
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Picture-in-picture for the room (board 96). Dart side: lib/player/pip.dart
 * (channel `app.synctogether/pip`).
 *
 * `support` answers whether this device offers it and whether the person left
 * it on for the app; `configure` arms or disarms entering on leaving the app
 * (auto-enter on 12+, `onUserLeaveHint` before) and sets the aspect ratio and
 * the play/pause and back actions; `enter` goes in now (the PiP key);
 * `openSettings` is the per-app PiP page. Events go back as `event` calls:
 * `mode` (inPip) and `action` (id).
 */
class Pip(private val activity: MainActivity) {
  private var channel: MethodChannel? = null
  private var armed = false
  private var width = 16
  private var height = 9
  private var playing = false
  private var receiver: BroadcastReceiver? = null

  fun register(messenger: BinaryMessenger) {
    val ch = MethodChannel(messenger, "app.synctogether/pip")
    channel = ch
    ch.setMethodCallHandler { call, result ->
      when (call.method) {
        "support" -> result.success(mapOf("supported" to supported(), "enabled" to enabled()))
        "configure" -> {
          armed = call.argument<Boolean>("armed") ?: false
          width = call.argument<Int>("w") ?: 16
          height = call.argument<Int>("h") ?: 9
          playing = call.argument<Boolean>("playing") ?: false
          apply()
          result.success(null)
        }
        "enter" -> result.success(enter())
        "close" -> {
          // The room ended or the person was removed: do not leave a dead
          // picture floating over the home screen.
          activity.moveTaskToBack(true)
          result.success(null)
        }
        "openSettings" -> {
          try {
            activity.startActivity(
              Intent("android.settings.PICTURE_IN_PICTURE_SETTINGS")
                .setData(Uri.parse("package:" + activity.packageName)),
            )
            result.success(true)
          } catch (_: Exception) {
            result.success(false)
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  fun supported(): Boolean =
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
      activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

  /** The per-app switch in Settings. Unknown (older APIs) counts as on. */
  fun enabled(): Boolean {
    if (!supported()) return false
    return try {
      val ops = activity.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
      @Suppress("DEPRECATION")
      ops.checkOpNoThrow(
        AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
        android.os.Process.myUid(),
        activity.packageName,
      ) == AppOpsManager.MODE_ALLOWED
    } catch (_: Exception) {
      true
    }
  }

  private fun clampedRational(): Rational {
    val r = width.toDouble() / height.toDouble()
    return when {
      r > 2.39 -> Rational(239, 100)
      r < 1.0 / 2.39 -> Rational(100, 239)
      else -> Rational(width, height)
    }
  }

  private fun actions(): List<RemoteAction> {
    fun action(id: String, icon: Int, title: String): RemoteAction {
      val intent = Intent(ACTION).setPackage(activity.packageName).putExtra("id", id)
      val pending = PendingIntent.getBroadcast(
        activity,
        id.hashCode(),
        intent,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
      )
      return RemoteAction(Icon.createWithResource(activity, icon), title, title, pending)
    }
    return listOf(
      action("back", android.R.drawable.ic_media_rew, "Back 10 seconds"),
      if (playing) {
        action("playPause", android.R.drawable.ic_media_pause, "Pause")
      } else {
        action("playPause", android.R.drawable.ic_media_play, "Play")
      },
    )
  }

  private fun params(): PictureInPictureParams {
    val b = PictureInPictureParams.Builder()
      .setAspectRatio(clampedRational())
      .setActions(actions())
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      b.setAutoEnterEnabled(armed)
      b.setSeamlessResizeEnabled(false)
    }
    return b.build()
  }

  /** Keeps the system's copy of the parameters in step with the room. */
  private fun apply() {
    if (!supported()) return
    try {
      activity.setPictureInPictureParams(params())
    } catch (_: Exception) {
      // Not allowed right now (activity finishing): the next change retries.
    }
  }

  /** Called from [MainActivity.onUserLeaveHint]: only before auto-enter exists. */
  fun onUserLeaveHint() {
    if (armed && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enter()
  }

  fun enter(): Boolean {
    if (!supported() || !enabled()) return false
    return try {
      activity.enterPictureInPictureMode(params())
    } catch (_: Exception) {
      false
    }
  }

  fun onModeChanged(inPip: Boolean) {
    if (inPip) listen() else unlisten()
    channel?.invokeMethod("event", mapOf("type" to "mode", "inPip" to inPip))
  }

  private fun listen() {
    unlisten()
    val r = object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        val id = intent?.getStringExtra("id") ?: return
        channel?.invokeMethod("event", mapOf("type" to "action", "id" to id))
      }
    }
    receiver = r
    val filter = IntentFilter(ACTION)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      activity.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      @Suppress("UnspecifiedRegisterReceiverFlag") activity.registerReceiver(r, filter)
    }
  }

  private fun unlisten() {
    receiver?.let {
      try {
        activity.unregisterReceiver(it)
      } catch (_: Exception) {}
    }
    receiver = null
  }

  companion object {
    const val ACTION = "app.synctogether.android.PIP_ACTION"
  }
}
