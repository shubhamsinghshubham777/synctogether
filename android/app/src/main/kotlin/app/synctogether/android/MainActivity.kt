package app.synctogether.android

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.max

class MainActivity : FlutterActivity() {
  private var recorder: AudioRecord? = null
  private var reader: Thread? = null
  @Volatile private var latestPeak = 0.0
  private var pendingStart: MethodChannel.Result? = null
  private var notificationRequestInFlight = false
  private val photoPicker = PhotoPicker(this)

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // Live input level for the "Test your mic" meter. WebRTC only captures
    // once a track rides a peer connection, so the dialog reads the mic
    // itself. Same contract as the desktop runners: start / peak / stop.
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.synctogether/mic_level")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "start" -> start(result)
          "peak" -> result.success(latestPeak)
          "stop" -> {
            stop()
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }
    // Persistable SAF grants, stat and ranged reads for content:// picks.
    MediaAccess.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
    // "From Photos": the system photo picker, no permission.
    photoPicker.register(flutterEngine.dartExecutor.binaryMessenger)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.synctogether/background_call")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "start" -> {
            try {
              startCallService(
                call.argument<Boolean>("mic") ?: false,
                call.argument<Boolean>("cam") ?: false,
                call.argument<String>("title") ?: "SyncTogether",
              )
              result.success(null)
            } catch (e: Exception) {
              result.error("start_failed", e.message, null)
            }
          }
          "stop" -> {
            stopService(Intent(this, CallForegroundService::class.java))
            result.success(null)
          }
          // Lets Dart learn the real state when the OS refused or killed it.
          "isRunning" -> result.success(CallForegroundService.running)
          else -> result.notImplemented()
        }
      }
  }

  private fun startCallService(mic: Boolean, cam: Boolean, title: String) {
    // POST_NOTIFICATIONS is a runtime permission on 13+. Without it the service
    // still runs, just without a visible notification, so it is optional: asked
    // once, only after the user turns the mic or camera on (their own prompt
    // is settled by then), and never over another pending request.
    if ((mic || cam) && Build.VERSION.SDK_INT >= 33 &&
      pendingStart == null && !notificationRequestInFlight &&
      checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
    ) {
      val prefs = getSharedPreferences("background_call", MODE_PRIVATE)
      if (!prefs.getBoolean("asked_notifications", false)) {
        prefs.edit().putBoolean("asked_notifications", true).apply()
        notificationRequestInFlight = true
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
      }
    }
    val intent = Intent(this, CallForegroundService::class.java)
      .putExtra(CallForegroundService.EXTRA_TITLE, title)
      .putExtra(CallForegroundService.EXTRA_MIC, mic)
      .putExtra(CallForegroundService.EXTRA_CAM, cam)
    startForegroundService(intent)
  }

  private fun start(result: MethodChannel.Result) {
    stop()
    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
      PackageManager.PERMISSION_GRANTED
    ) {
      result.success(open())
      return
    }
    // Answer comes back in onRequestPermissionsResult. A second start while
    // the prompt is up replaces the first, which is answered false.
    pendingStart?.success(false)
    pendingStart = result
    requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQUEST)
  }

  @Deprecated("Deprecated in Java")
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    if (photoPicker.onActivityResult(requestCode, resultCode, data)) return
    @Suppress("DEPRECATION")
    super.onActivityResult(requestCode, resultCode, data)
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode == NOTIFICATION_REQUEST) notificationRequestInFlight = false
    if (requestCode != MIC_REQUEST) return
    val pending = pendingStart ?: return
    pendingStart = null
    val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
    pending.success(granted && open())
  }

  private fun open(): Boolean {
    val rate = 16000
    val min = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
    if (min <= 0) return false
    val record = try {
      AudioRecord(
        MediaRecorder.AudioSource.MIC, rate, AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT, min * 2,
      )
    } catch (e: Exception) {
      return false
    }
    if (record.state != AudioRecord.STATE_INITIALIZED) {
      record.release()
      return false
    }
    record.startRecording()
    recorder = record
    reader = Thread {
      val buffer = ShortArray(min)
      while (!Thread.currentThread().isInterrupted) {
        val n = record.read(buffer, 0, buffer.size)
        if (n <= 0) break
        var peak = 0
        for (i in 0 until n) peak = max(peak, abs(buffer[i].toInt()))
        latestPeak = peak / 32768.0
      }
    }.also { it.start() }
    return true
  }

  private fun stop() {
    reader?.interrupt()
    reader = null
    recorder?.let {
      try {
        it.stop()
      } catch (_: IllegalStateException) {}
      it.release()
    }
    recorder = null
    latestPeak = 0.0
  }

  override fun onDestroy() {
    stop()
    super.onDestroy()
  }

  private companion object {
    const val MIC_REQUEST = 4721
    const val NOTIFICATION_REQUEST = 4723
  }
}
