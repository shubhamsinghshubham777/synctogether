package app.synctogether.android

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * "From Photos": the system photo picker filtered to videos. Dart side:
 * lib/player/photo_picker.dart (channel `app.synctogether/photo_picker`).
 *
 * The photo picker (API 33+, and 30+ with the R extension 2 backport) runs in
 * another process, so the app needs no storage or media permission and shows no
 * prompt. It returns a `content://` URI with a temporary read grant, which the
 * existing media_access channel can stat, play and range-read. Older devices
 * fall back to ACTION_GET_CONTENT, which is the same shape of result.
 */
class PhotoPicker(private val activity: Activity) {
  private var pending: MethodChannel.Result? = null

  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, "app.synctogether/photo_picker").setMethodCallHandler { call, result ->
      if (call.method == "pickVideo") pick(result) else result.notImplemented()
    }
  }

  private fun pickerAvailable(): Boolean =
    Build.VERSION.SDK_INT >= 33 ||
      (Build.VERSION.SDK_INT >= 30 && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)

  private fun pick(result: MethodChannel.Result) {
    // A second tap while the picker is up replaces the first, which is a cancel.
    pending?.success(null)
    pending = result
    val intent = if (pickerAvailable()) {
      Intent(MediaStore.ACTION_PICK_IMAGES).setType("video/*")
    } else {
      Intent(Intent.ACTION_GET_CONTENT).setType("video/*").addCategory(Intent.CATEGORY_OPENABLE)
    }
    try {
      activity.startActivityForResult(intent, REQUEST)
    } catch (e: Exception) {
      pending = null
      result.success(null)
    }
  }

  /** True when the result was ours. */
  fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != REQUEST) return false
    val result = pending ?: return true
    pending = null
    val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
    if (uri == null) {
      result.success(null)
      return true
    }
    var name: String? = null
    try {
      activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        ?.use { c ->
          if (c.moveToFirst()) {
            val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (n >= 0 && !c.isNull(n)) name = c.getString(n)
          }
        }
    } catch (_: Exception) {}
    result.success(mapOf("uri" to uri.toString(), "name" to (name ?: uri.lastPathSegment ?: "video")))
    return true
  }

  private companion object {
    const val REQUEST = 4725
  }
}
