package app.synctogether.android

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * Access to the `content://` documents the SAF picker returns, which have no
 * filesystem path. Dart side: lib/player/media_access.dart (channel
 * `app.synctogether/media_access`). The picker itself is saf_util's
 * ACTION_OPEN_DOCUMENT; it does not keep the grant, so this takes it:
 *
 *  - takePersistable / releasePersisted: a read grant that survives restarts.
 *  - stat: display name (the URI tail is `video:1234`), size, MIME; null when
 *    the document cannot be queried any more. This is the real "can I still
 *    open it" check, not the grant list.
 *  - readRange: bytes [offset, offset+length) through a ParcelFileDescriptor
 *    (the R2 upload path). Throws not_seekable for a provider that serves a
 *    pipe. Runs off the main thread; replies are posted back to it.
 */
object MediaAccess {
  private val io = Executors.newFixedThreadPool(2)
  private val main = Handler(Looper.getMainLooper())

  fun register(messenger: BinaryMessenger, context: Context) {
    MethodChannel(messenger, "app.synctogether/media_access").setMethodCallHandler { call, result ->
      val uri = call.argument<String>("uri")?.let { Uri.parse(it) }
      if (uri == null) {
        result.notImplemented()
        return@setMethodCallHandler
      }
      when (call.method) {
        "takePersistable" -> result.success(takePersistable(context, uri))
        "releasePersisted" -> {
          release(context, uri)
          result.success(null)
        }
        "stat" -> io.execute { reply(result) { stat(context, uri) } }
        "readRange" -> io.execute { reply(result) { readRange(context, uri, call) } }
        else -> result.notImplemented()
      }
    }
  }

  private fun reply(result: MethodChannel.Result, body: () -> Any?) {
    try {
      val value = body()
      main.post { result.success(value) }
    } catch (e: NotSeekable) {
      main.post { result.error("not_seekable", e.message, null) }
    } catch (e: Exception) {
      // SecurityException (grant lost), FileNotFoundException, provider death:
      // all mean "cannot read it", which Dart treats as unavailable.
      main.post { result.success(null) }
    }
  }

  private class NotSeekable(message: String) : IOException(message)

  private fun takePersistable(context: Context, uri: Uri): Boolean = try {
    context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    true
  } catch (e: Exception) {
    false // provider offers no persistable grant, or the temporary one is gone
  }

  private fun release(context: Context, uri: Uri) {
    try {
      context.contentResolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    } catch (_: Exception) {}
  }

  private fun stat(context: Context, uri: Uri): Map<String, Any?>? {
    val resolver = context.contentResolver
    var name: String? = null
    var size: Long? = null
    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
      ?.use { c ->
        if (c.moveToFirst()) {
          val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
          val s = c.getColumnIndex(OpenableColumns.SIZE)
          if (n >= 0 && !c.isNull(n)) name = c.getString(n)
          if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
        }
      }
    // Prove the bytes are reachable (a query can succeed on a revoked document).
    resolver.openFileDescriptor(uri, "r")?.use { pfd ->
      if (size == null || size!! <= 0) size = pfd.statSize.takeIf { it > 0 }
    } ?: return null
    return mapOf(
      "name" to (name ?: uri.lastPathSegment ?: "video"),
      "size" to size,
      "mime" to resolver.getType(uri),
    )
  }

  private fun readRange(context: Context, uri: Uri, call: MethodCall): ByteArray {
    val offset = (call.argument<Number>("offset") ?: 0).toLong()
    val length = (call.argument<Number>("length") ?: 0).toInt()
    val pfd = context.contentResolver.openFileDescriptor(uri, "r")
      ?: throw IOException("no descriptor")
    pfd.use {
      FileInputStream(it.fileDescriptor).channel.use { channel ->
        try {
          channel.position(offset)
        } catch (e: IOException) {
          throw NotSeekable("provider is not seekable")
        }
        val buffer = ByteBuffer.allocate(length)
        while (buffer.hasRemaining()) {
          if (channel.read(buffer) < 0) break
        }
        return buffer.array().copyOf(buffer.position())
      }
    }
  }
}
