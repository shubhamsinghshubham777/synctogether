package app.synctogether.android

import android.Manifest
import android.content.pm.PackageManager
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

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
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
  }
}
