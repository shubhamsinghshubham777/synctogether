package app.synctogether.android

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service held for as long as a room holds a LiveKit session, so
 * Android keeps the microphone, camera and playback alive once the app is
 * backgrounded. Started from the foreground only (Android 14 forbids starting
 * a microphone/camera service from the background). Nothing runs inside it:
 * its job is to be a process-priority anchor with a visible notification.
 */
class CallForegroundService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val title = intent?.getStringExtra(EXTRA_TITLE) ?: "SyncTogether"
    val wantMic = intent?.getBooleanExtra(EXTRA_MIC, false) ?: false
    val wantCam = intent?.getBooleanExtra(EXTRA_CAM, false) ?: false
    ensureChannel()
    val notification = buildNotification(title)
    // Microphone / camera types only exist from API 30, and a type whose
    // runtime permission is not held throws on Android 14+, so ask for them
    // only while granted. Media playback (API 29) is always declared.
    var type = 0
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        if (wantMic && granted(Manifest.permission.RECORD_AUDIO)) {
          type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }
        if (wantCam && granted(Manifest.permission.CAMERA)) {
          type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        }
      }
    }
    var started = tryStartForeground(notification, type)
    if (!started && type != ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK &&
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    ) {
      // Re-typing from the background (Android 14+) or a revoked permission
      // can refuse the richer type; playback alone is still worth keeping.
      started = tryStartForeground(notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
    }
    if (!started) {
      // Never stop before a startForeground attempt has been made, or the
      // OS raises ForegroundServiceDidNotStartInTimeException.
      running = false
      stopSelf()
    } else {
      running = true
    }
    return START_NOT_STICKY
  }

  private fun tryStartForeground(notification: Notification, type: Int): Boolean =
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        startForeground(NOTIFICATION_ID, notification, type)
      } else {
        startForeground(NOTIFICATION_ID, notification)
      }
      true
    } catch (e: Exception) {
      false
    }

  // The user swiped the app away: nothing is left to keep alive.
  override fun onTaskRemoved(rootIntent: Intent?) {
    running = false
    stopSelf()
    super.onTaskRemoved(rootIntent)
  }

  override fun onDestroy() {
    running = false
    super.onDestroy()
  }

  private fun granted(permission: String) =
    checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

  private fun ensureChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (manager.getNotificationChannel(CHANNEL_ID) != null) return
    manager.createNotificationChannel(
      NotificationChannel(CHANNEL_ID, "Active room", NotificationManager.IMPORTANCE_LOW).apply {
        description = "Shown while you are in a room so voice and playback keep running."
        setShowBadge(false)
      },
    )
  }

  private fun buildNotification(title: String): Notification {
    val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
      PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
    }
    val builder =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID)
      else @Suppress("DEPRECATION") Notification.Builder(this)
    return builder
      .setSmallIcon(applicationInfo.icon)
      .setContentTitle(title)
      .setContentText("In a room - tap to return")
      .setOngoing(true)
      .setContentIntent(open)
      .build()
  }

  companion object {
    const val EXTRA_TITLE = "title"
    const val EXTRA_MIC = "mic"
    const val EXTRA_CAM = "cam"
    /** Whether the service currently holds a foreground notification. */
    @Volatile var running = false
    private const val CHANNEL_ID = "active_room"
    private const val NOTIFICATION_ID = 4722
  }
}
