package dev.amuse.amuse

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.util.concurrent.Executors

/// Folders the user grants through Android's folder picker (the Storage
/// Access Framework), which reaches internal storage and SD cards without
/// any storage permission. Grants are persisted, so saved folders keep
/// working after a restart.
class MainActivity : FlutterActivity() {
    private val io = Executors.newFixedThreadPool(4)
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "amuse/documents")
            .setMethodCallHandler(::onCall)
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> pickFolder(result)
            "list" -> background(result) { list(Uri.parse(call.argument<String>("uri"))) }
            "read" -> background(result) {
                read(Uri.parse(call.argument<String>("uri")), call.argument<Number>("offset")!!.toLong(),
                    call.argument<Int>("length")!!)
            }
            "release" -> background(result) {
                runCatching {
                    contentResolver.releasePersistableUriPermission(
                        Uri.parse(call.argument<String>("uri")), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                null
            }
            else -> result.notImplemented()
        }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        pendingPick?.success(null)
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        startActivityForResult(intent, PICK_FOLDER)
    }

    @Deprecated("FlutterActivity has no Activity Result API hook")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_FOLDER) return
        val result = pendingPick ?: return
        pendingPick = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) return result.success(null)
        background(result) {
            contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val root = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            mapOf("uri" to tree.toString(), "name" to (displayName(root) ?: "Folder"))
        }
    }

    /// Children of a picked folder or of any folder below it. Ids are
    /// document URIs built under the tree, the only form the grant covers.
    private fun list(folder: Uri): List<Map<String, Any?>> {
        val parentId = if (DocumentsContract.isDocumentUri(this, folder)) DocumentsContract.getDocumentId(folder)
        else DocumentsContract.getTreeDocumentId(folder)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(folder, parentId)
        val columns = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE)
        val entries = mutableListOf<Map<String, Any?>>()
        contentResolver.query(children, columns, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                entries += mapOf(
                    "uri" to DocumentsContract.buildDocumentUriUsingTree(folder, c.getString(0)).toString(),
                    "name" to c.getString(1),
                    "folder" to (c.getString(2) == Document.MIME_TYPE_DIR),
                )
            }
        } ?: throw IllegalStateException("Couldn't open this folder")
        return entries
    }

    /// Up to [length] bytes from [offset]; fewer only at the end of the file.
    private fun read(uri: Uri, offset: Long, length: Int): ByteArray {
        contentResolver.openFileDescriptor(uri, "r")!!.use { pfd ->
            FileInputStream(pfd.fileDescriptor).use { input ->
                input.channel.position(offset)
                val buffer = ByteArray(length)
                var filled = 0
                while (filled < length) {
                    val n = input.read(buffer, filled, length - filled)
                    if (n < 0) break
                    filled += n
                }
                return if (filled == length) buffer else buffer.copyOf(filled)
            }
        }
    }

    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    /// Runs [job] off the UI thread; a revoked grant or removed SD card
    /// surfaces as a SecurityException, reported as "denied".
    private fun background(result: MethodChannel.Result, job: () -> Any?) {
        io.execute {
            try {
                val value = job()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("denied", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message, null) }
            }
        }
    }

    private companion object {
        const val PICK_FOLDER = 4021
    }
}
