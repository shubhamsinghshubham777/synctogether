package app.synctogether.android

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Push notifications over FCM. Same contract as the Apple and Windows runners
 * (`app.synctogether/push`), so the Dart side is one implementation. Dart side:
 * lib/pairing/push_service.dart.
 *
 * Nothing here prompts by itself: `permission` only reads, and `request` is the
 * one call that shows the system dialog (Android 13+).
 */
object Push {
  private const val PREFS = "push"
  private const val REQUEST = 4725
  const val CHANNEL_CALLS = "calls"
  const val CHANNEL_DEFAULT = "default"
  const val EXTRA_ROUTE = "route"

  private var channel: MethodChannel? = null
  private var pendingRoute: String? = null
  private var dartReady = false
  private var pendingPermission: MethodChannel.Result? = null
  private var lastToken: String? = null

  // -------------------------------------------------------------- Firebase

  /** Initialises the default Firebase app once, from stored options. */
  fun initFirebaseFromStoredOptions(context: Context) {
    val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    val apiKey = p.getString("apiKey", null)
    val appId = p.getString("appId", null)
    val projectId = p.getString("projectId", null)
    val senderId = p.getString("senderId", null)
    if (apiKey == null || appId == null || projectId == null || senderId == null) return
    initFirebase(context, apiKey, appId, projectId, senderId)
  }

  private fun initFirebase(
    context: Context, apiKey: String, appId: String, projectId: String, senderId: String,
  ) {
    if (FirebaseApp.getApps(context).isNotEmpty()) return
    FirebaseApp.initializeApp(
      context,
      FirebaseOptions.Builder()
        .setApiKey(apiKey)
        .setApplicationId(appId)
        .setProjectId(projectId)
        .setGcmSenderId(senderId)
        .build(),
    )
  }

  private fun firebaseReady(context: Context) = FirebaseApp.getApps(context).isNotEmpty()

  // -------------------------------------------------------------- channels

  fun ensureChannels(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java) ?: return
    manager.createNotificationChannel(
      NotificationChannel(CHANNEL_CALLS, "Calls", NotificationManager.IMPORTANCE_HIGH).apply {
        description = "When your person rings you in Our Room"
      },
    )
    manager.createNotificationChannel(
      NotificationChannel(CHANNEL_DEFAULT, "Date nights and updates", NotificationManager.IMPORTANCE_DEFAULT)
        .apply { description = "Date night reminders, your watchlist and your reunion countdown" },
    )
  }

  // --------------------------------------------------------------- channel

  fun register(messenger: BinaryMessenger, activity: Activity) {
    val channel = MethodChannel(messenger, "app.synctogether/push")
    this.channel = channel
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "configure" -> {
          dartReady = true
          val firebase = call.argument<Map<String, String>>("firebase")
          if (firebase == null) {
            result.success(null)
            return@setMethodCallHandler
          }
          val keys = listOf("apiKey", "appId", "projectId", "senderId")
          if (keys.any { firebase[it].isNullOrBlank() }) {
            result.success(null)
            return@setMethodCallHandler
          }
          activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
            keys.forEach { putString(it, firebase[it]) }
          }.apply()
          initFirebase(
            activity.applicationContext, firebase["apiKey"]!!, firebase["appId"]!!,
            firebase["projectId"]!!, firebase["senderId"]!!,
          )
          result.success(null)
        }
        "permission" -> result.success(permission(activity))
        "request" -> request(activity, result)
        "token" -> fetchToken(activity, result)
        "launchRoute" -> {
          val route = pendingRoute
          pendingRoute = null
          result.success(route)
        }
        "openSettings" -> {
          activity.startActivity(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
              .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName),
          )
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }

  // ------------------------------------------------------------ permission

  private fun asked(context: Context) =
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("asked", false)

  /** `unsupported` when this build has no Firebase project: nothing to receive. */
  private fun permission(context: Context): String {
    if (!firebaseReady(context)) return "unsupported"
    val manager = context.getSystemService(NotificationManager::class.java)
    if (Build.VERSION.SDK_INT >= 33 &&
      context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
      PackageManager.PERMISSION_GRANTED
    ) {
      return if (asked(context)) "denied" else "unknown"
    }
    return if (manager?.areNotificationsEnabled() == false) "denied" else "granted"
  }

  private fun request(activity: Activity, result: MethodChannel.Result) {
    if (!firebaseReady(activity)) return result.success("unsupported")
    if (Build.VERSION.SDK_INT < 33 ||
      activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
      PackageManager.PERMISSION_GRANTED
    ) {
      return result.success(permission(activity))
    }
    // A second request while the dialog is up replaces the first.
    pendingPermission?.success("unknown")
    pendingPermission = result
    activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("asked", true).apply()
    activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST)
  }

  /** From the activity's onRequestPermissionsResult; true when it was ours. */
  fun onPermissionResult(activity: Activity, requestCode: Int): Boolean {
    if (requestCode != REQUEST) return false
    pendingPermission?.success(permission(activity))
    pendingPermission = null
    return true
  }

  // ----------------------------------------------------------------- token

  private fun fetchToken(context: Context, result: MethodChannel.Result) {
    if (!firebaseReady(context)) return result.success(null)
    FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
      val token = if (task.isSuccessful) task.result else null
      lastToken = token
      result.success(token?.let { mapOf("token" to it, "environment" to "production") })
    }
  }

  fun deliverToken(token: String) {
    lastToken = token
    channel?.invokeMethod("token", mapOf("token" to token, "environment" to "production"))
  }

  // ------------------------------------------------------------------ taps

  /** Reads the route a tapped notification carried, from the launching intent. */
  fun handleIntent(intent: Intent?) {
    val route = intent?.getStringExtra(EXTRA_ROUTE) ?: return
    // One shot: a rotation re-delivers the same intent and must not re-navigate.
    intent.removeExtra(EXTRA_ROUTE)
    tapped(route)
  }

  private fun tapped(route: String) {
    val c = channel
    if (dartReady && c != null) c.invokeMethod("tap", mapOf("route" to route)) else pendingRoute = route
  }

  // ----------------------------------------------- foreground presentation

  /** FCM shows nothing itself while the app is open, so we do - like Apple does. */
  fun showForeground(context: Context, message: RemoteMessage) {
    val data = message.data
    val title = message.notification?.title ?: data["title"] ?: return
    val body = message.notification?.body ?: data["body"] ?: ""
    val route = data[EXTRA_ROUTE]
    val urgent = data["kind"] == "call"
    ensureChannels(context)
    val tap = PendingIntent.getActivity(
      context, route.hashCode(),
      Intent(context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        .putExtra(EXTRA_ROUTE, route),
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Notification.Builder(context, if (urgent) CHANNEL_CALLS else CHANNEL_DEFAULT)
    } else {
      @Suppress("DEPRECATION") Notification.Builder(context)
    }
    val notification = builder
      .setSmallIcon(context.applicationInfo.icon)
      .setContentTitle(title)
      .setContentText(body)
      .setAutoCancel(true)
      .setContentIntent(tap)
      .build()
    context.getSystemService(NotificationManager::class.java)
      ?.notify((data["kind"] ?: "push").hashCode(), notification)
  }
}

/** Receives the token refreshes and any message FCM does not display itself. */
class PushMessagingService : FirebaseMessagingService() {
  override fun onNewToken(token: String) {
    Push.deliverToken(token)
  }

  override fun onMessageReceived(message: RemoteMessage) {
    // Background messages with a notification block are drawn by the system and
    // never reach here. What does reach here is the app being open (show a
    // banner) or a data-only message (show it the same way).
    Push.showForeground(applicationContext, message)
  }
}
