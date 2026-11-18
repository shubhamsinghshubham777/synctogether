package app.synctogether.android

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Tells the pre-show check when a call or another app takes the microphone and
 * when the input changes (a headset in or out). Dart side:
 * lib/pairing/pre_show_probes.dart (channel `app.synctogether/audio_events`).
 * `start` and `stop` bound the listening to the time the sheet is open; events
 * go back as `event` calls: `interrupted`, `resumed`, `input` (+ name, builtIn,
 * bluetooth). Same contract as the iOS and macOS runners.
 */
object AudioEvents {
  private var channel: MethodChannel? = null
  private var recording: AudioManager.AudioRecordingCallback? = null
  private var devices: AudioDeviceCallback? = null
  private var silenced = false
  private val main = Handler(Looper.getMainLooper())

  fun register(messenger: BinaryMessenger, context: Context) {
    val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val ch = MethodChannel(messenger, "app.synctogether/audio_events")
    channel = ch
    ch.setMethodCallHandler { call, result ->
      when (call.method) {
        "start" -> {
          listen(audio)
          result.success(null)
        }
        "stop" -> {
          unlisten(audio)
          result.success(null)
        }
        "useBuiltIn" -> result.success(useBuiltIn(audio))
        "audioState" -> result.success(audioState(audio))
        "useBuiltInOutput" -> result.success(useBuiltInOutput(audio))
        else -> result.notImplemented()
      }
    }
  }

  private fun send(payload: Map<String, Any?>) {
    main.post { channel?.invokeMethod("event", payload) }
  }

  private fun listen(audio: AudioManager) {
    unlisten(audio)
    silenced = false
    // A call (or any app the system lets in ahead of us) silences our capture
    // without stopping it; that is the interruption, and its end is the resume.
    val rec = object : AudioManager.AudioRecordingCallback() {
      override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val now = configs.any { it.isClientSilenced }
        if (now == silenced) return
        silenced = now
        send(mapOf("type" to if (now) "interrupted" else "resumed"))
      }
    }
    recording = rec
    audio.registerAudioRecordingCallback(rec, main)
    val dev = object : AudioDeviceCallback() {
      override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = sendInput(audio)
      override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = sendInput(audio)
    }
    devices = dev
    audio.registerAudioDeviceCallback(dev, main)
  }

  private fun unlisten(audio: AudioManager) {
    recording?.let { audio.unregisterAudioRecordingCallback(it) }
    recording = null
    devices?.let { audio.unregisterAudioDeviceCallback(it) }
    devices = null
  }

  private fun isBluetooth(t: Int): Boolean =
    t == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
      (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && t == AudioDeviceInfo.TYPE_BLE_HEADSET)

  private fun isHeadset(t: Int): Boolean =
    isBluetooth(t) ||
      t == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
      t == AudioDeviceInfo.TYPE_USB_HEADSET ||
      t == AudioDeviceInfo.TYPE_USB_DEVICE

  private fun sendInput(audio: AudioManager) {
    val inputs = audio.getDevices(AudioManager.GET_DEVICES_INPUTS)
    val headset = inputs.firstOrNull { isHeadset(it.type) }
    val info = headset ?: inputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC } ?: return
    send(
      mapOf(
        "type" to "input",
        "name" to info.productName.toString(),
        "builtIn" to (headset == null),
        "bluetooth" to isBluetooth(info.type),
      ),
    )
  }

  /** The media volume and where the sound goes, for the Sound row. */
  private fun audioState(audio: AudioManager): Map<String, Any?> {
    val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
    val volume = if (max > 0) audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max else null
    val outs = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
    val external = outs.firstOrNull {
      when (it.type) {
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_HDMI -> true
        else -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
          it.type == AudioDeviceInfo.TYPE_BLE_HEADSET
      }
    }
    val speaker = outs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
    val info = external ?: speaker
    val kind = when {
      external == null -> "builtIn"
      isBluetooth(external.type) || external.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
      external.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
        external.type == AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired"
      else -> "other"
    }
    return mapOf(
      "volume" to volume,
      "name" to info?.productName?.toString(),
      "kind" to kind,
      "canBuiltIn" to (speaker != null),
    )
  }

  /** Ask the system to use the phone's own speaker; returns its name. */
  private fun useBuiltInOutput(audio: AudioManager): Map<String, Any?> {
    val speaker = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
      .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
      ?: return mapOf("ok" to false)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      audio.setCommunicationDevice(speaker)
    }
    return mapOf("ok" to true, "name" to speaker.productName.toString())
  }

  /** Back to the phone's own microphone; returns its name. */
  private fun useBuiltIn(audio: AudioManager): Map<String, Any?> {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      audio.clearCommunicationDevice()
    } else {
      @Suppress("DEPRECATION") audio.stopBluetoothSco()
      @Suppress("DEPRECATION") audio.isBluetoothScoOn = false
    }
    val mic = audio.getDevices(AudioManager.GET_DEVICES_INPUTS)
      .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
      ?: return mapOf("ok" to false)
    return mapOf("ok" to true, "name" to mic.productName.toString())
  }
}
