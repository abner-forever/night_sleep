package com.abner.night_sleep

import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import kotlin.math.max

/**
 * 管理导出目录、自动写入文件和默认导入。
 *
 * Android 10 起默认目录是系统“下载/夜深”，通过 MediaStore 写入，不需要存储权限；
 * Android 9 及以下退到应用专属文件目录。自定义目录使用 Storage Access Framework
 * 的 ACTION_OPEN_DOCUMENT_TREE，并持久保存目录授权。
 */
class ExportStorageHandler(private val activity: Activity) :
    MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val preferences =
        activity.getSharedPreferences("night_sleep_export", Activity.MODE_PRIVATE)
    private var pendingChooseResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "location" -> result.success(locationInfo())
            "chooseLocation" -> chooseLocation(result)
            "resetLocation" -> {
                resetCustomLocation()
                result.success(locationInfo())
            }
            "save" -> {
                val sources = try {
                    parseSources(call)
                } catch (error: Exception) {
                    result.error(
                        "invalid_source",
                        error.message ?: "导出文件已失效，请重新生成。",
                        null
                    )
                    return
                }
                runAsync(result) { saveAll(sources) }
            }
            "latestBackup" -> runAsync(result) { latestBackupPath() }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ): Boolean {
        if (requestCode != REQUEST_CODE_CHOOSE_DIRECTORY) return false

        val result = pendingChooseResult ?: return true
        pendingChooseResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }

        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            val previous = customTreeUri()
            if (previous != null && previous != uri) releasePermission(previous)
            preferences.edit().putString(KEY_TREE_URI, uri.toString()).apply()
            result.success(locationInfo())
        } catch (error: Exception) {
            result.error(
                "location_unavailable",
                error.message ?: "无法保存这个目录的访问权限。",
                null
            )
        }
        return true
    }

    fun dispose() {
        val pending = pendingChooseResult
        pendingChooseResult = null
        pending?.error(
            "activity_unavailable",
            "目录选择页面已关闭，请返回应用后重试。",
            null
        )
        executor.shutdown()
    }

    private fun chooseLocation(result: MethodChannel.Result) {
        if (pendingChooseResult != null) {
            result.error("location_busy", "已有目录选择页面正在打开。", null)
            return
        }
        pendingChooseResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        }
        try {
            activity.startActivityForResult(intent, REQUEST_CODE_CHOOSE_DIRECTORY)
        } catch (error: Exception) {
            pendingChooseResult = null
            result.error(
                "location_unavailable",
                error.message ?: "无法打开目录选择页面。",
                null
            )
        }
    }

    private fun locationInfo(): Map<String, Any> {
        val tree = customTreeUri()
        if (tree != null) {
            try {
                return mapOf(
                    "label" to "自选文件夹：${treeDisplayName(tree)}",
                    "custom" to true,
                    "canChoose" to true
                )
            } catch (_: Exception) {
                resetCustomLocation()
            }
        }
        return mapOf(
            "label" to defaultLocationLabel(),
            "custom" to false,
            "canChoose" to true
        )
    }

    private fun customTreeUri(): Uri? {
        val raw = preferences.getString(KEY_TREE_URI, null) ?: return null
        val uri = Uri.parse(raw)
        val permission = activity.contentResolver.persistedUriPermissions
            .firstOrNull { it.uri == uri && it.isReadPermission && it.isWritePermission }
        if (permission == null) {
            preferences.edit().remove(KEY_TREE_URI).apply()
            return null
        }
        return uri
    }

    private fun resetCustomLocation() {
        val current = preferences.getString(KEY_TREE_URI, null)
            ?.let(Uri::parse)
        if (current != null) releasePermission(current)
        preferences.edit().remove(KEY_TREE_URI).apply()
    }

    private fun releasePermission(uri: Uri) {
        try {
            activity.contentResolver.releasePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: Exception) {
            // 权限已经失效时无需再释放。
        }
    }

    private fun defaultLocationLabel(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "下载/$DEFAULT_FOLDER"
        } else {
            "应用文件/$DEFAULT_FOLDER"
        }

    private fun treeDisplayName(tree: Uri): String {
        val documentId = DocumentsContract.getTreeDocumentId(tree)
        val documentUri =
            DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
        activity.contentResolver.query(
            documentUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return tree.lastPathSegment ?: "自定义目录"
    }

    private fun parseSources(call: MethodCall): List<SourceFile> {
        val rawFiles = call.argument<List<*>>("files")
            ?: throw IllegalArgumentException("没有要保存的文件。")
        require(rawFiles.isNotEmpty()) { "没有要保存的文件。" }
        val cacheRoot = activity.cacheDir.canonicalFile
        val cachePrefix = cacheRoot.path + File.separator
        return rawFiles.map { raw ->
            val values = raw as? Map<*, *>
                ?: throw IllegalArgumentException("导出文件参数不完整。")
            val path = values["path"] as? String
                ?: throw IllegalArgumentException("导出文件路径缺失。")
            val source = File(path).canonicalFile
            require(source.path.startsWith(cachePrefix)) {
                "导出文件不在应用缓存目录中。"
            }
            require(source.isFile && source.canRead()) {
                "导出文件已失效，请重新生成。"
            }
            SourceFile(
                file = source,
                displayName = sanitizeFileName(
                    values["fileName"] as? String ?: source.name
                ),
                mimeType = values["mimeType"] as? String
                    ?: "application/octet-stream"
            )
        }
    }

    private fun saveAll(sources: List<SourceFile>): Map<String, Any> {
        val custom = customTreeUri()
        var saved = 0
        var failed = false
        for (source in sources) {
            try {
                if (custom != null) {
                    saveToCustomTree(custom, source)
                } else {
                    saveToDefaultLocation(source)
                }
                saved++
            } catch (_: Exception) {
                failed = true
                break
            }
        }
        return mapOf(
            "savedCount" to saved,
            "fileCount" to sources.size,
            "failed" to failed
        )
    }

    private fun saveToDefaultLocation(source: SourceFile) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveToMediaStore(source)
        } else {
            saveToLegacyDownloads(source)
        }
    }

    private fun saveToMediaStore(source: SourceFile) {
        val resolver = activity.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$DEFAULT_FOLDER/"
        val existing = resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND " +
                "${MediaStore.MediaColumns.DISPLAY_NAME}=?",
            arrayOf(relativePath, source.displayName),
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                ContentUris.withAppendedId(collection, cursor.getLong(0))
            } else {
                null
            }
        }

        val isNew = existing == null
        val target = existing ?: run {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, source.displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, source.mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            resolver.insert(collection, values)
                ?: throw IOException("无法在下载目录创建文件。")
        }

        try {
            writeFileToUri(source.file, target)
            if (isNew) {
                resolver.update(
                    target,
                    ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    },
                    null,
                    null
                )
            }
        } catch (error: Exception) {
            if (isNew) resolver.delete(target, null, null)
            throw error
        }
    }

    private fun saveToLegacyDownloads(source: SourceFile) {
        val base = activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: activity.filesDir
        val directory = File(base, DEFAULT_FOLDER).apply {
            if (!exists() && !mkdirs()) throw IOException("无法创建导出目录。")
        }
        source.file.copyTo(
            File(directory, source.displayName),
            overwrite = true
        )
    }

    private fun saveToCustomTree(tree: Uri, source: SourceFile) {
        val parent = treeRootDocumentUri(tree)
        val existing = findChildDocument(tree, source.displayName)
        val target = existing ?: DocumentsContract.createDocument(
            activity.contentResolver,
            parent,
            source.mimeType,
            source.displayName
        ) ?: throw IOException("无法在所选目录创建文件。")
        writeFileToUri(source.file, target)
    }

    private fun treeRootDocumentUri(tree: Uri): Uri {
        val documentId = DocumentsContract.getTreeDocumentId(tree)
        return DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
    }

    private fun childrenUri(tree: Uri): Uri {
        val documentId = DocumentsContract.getTreeDocumentId(tree)
        return DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
    }

    private fun findChildDocument(tree: Uri, displayName: String): Uri? {
        activity.contentResolver.query(
            childrenUri(tree),
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            ),
            null,
            null,
            null
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID
            )
            val nameIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            )
            while (cursor.moveToNext()) {
                if (cursor.getString(nameIndex) == displayName) {
                    return DocumentsContract.buildDocumentUriUsingTree(
                        tree,
                        cursor.getString(idIndex)
                    )
                }
            }
        }
        return null
    }

    private fun writeFileToUri(source: File, target: Uri) {
        val output = activity.contentResolver.openOutputStream(target, "wt")
            ?: throw IOException("系统没有返回可写文件。")
        output.use { targetStream ->
            source.inputStream().use { input ->
                input.copyTo(targetStream, DEFAULT_BUFFER_SIZE)
            }
        }
    }

    private fun latestBackupPath(): String? {
        val custom = customTreeUri()
        return if (custom != null) {
            latestCustomBackup(custom)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            latestMediaStoreBackup()
        } else {
            latestLegacyBackup()
        }
    }

    private fun latestMediaStoreBackup(): String? {
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$DEFAULT_FOLDER/"
        activity.contentResolver.query(
            collection,
            arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.DATE_MODIFIED
            ),
            "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND " +
                "(${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? OR " +
                "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?)",
            arrayOf(relativePath, "%.zip", "%.json"),
            "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val id = cursor.getLong(0)
            val name = cursor.getString(1)
            val uri = ContentUris.withAppendedId(collection, id)
            return copyUriToCache(uri, name)
        }
        return null
    }

    private fun latestLegacyBackup(): String? {
        val base = activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: activity.filesDir
        val directory = File(base, DEFAULT_FOLDER)
        return directory.listFiles()
            ?.filter(::isBackupFile)
            ?.maxByOrNull(File::lastModified)
            ?.path
    }

    private fun latestCustomBackup(tree: Uri): String? {
        var latestName: String? = null
        var latestId: String? = null
        var latestModified = Long.MIN_VALUE
        activity.contentResolver.query(
            childrenUri(tree),
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED
            ),
            null,
            null,
            null
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID
            )
            val nameIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            )
            val modifiedIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_LAST_MODIFIED
            )
            while (cursor.moveToNext()) {
                val name = cursor.getString(nameIndex)
                if (!isBackupName(name)) continue
                val modified =
                    if (cursor.isNull(modifiedIndex)) 0L
                    else cursor.getLong(modifiedIndex)
                if (modified >= latestModified) {
                    latestModified = max(modified, latestModified)
                    latestName = name
                    latestId = cursor.getString(idIndex)
                }
            }
        }
        val name = latestName ?: return null
        val id = latestId ?: return null
        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
        return copyUriToCache(uri, name)
    }

    private fun copyUriToCache(uri: Uri, displayName: String): String {
        val extension = displayName.substringAfterLast('.', "").lowercase()
        val target = File.createTempFile(
            "night-sleep-import-",
            ".$extension",
            activity.cacheDir
        )
        try {
            val input = activity.contentResolver.openInputStream(uri)
                ?: throw IOException("无法读取备份文件。")
            input.use { source ->
                target.outputStream().use { output ->
                    source.copyTo(output, DEFAULT_BUFFER_SIZE)
                }
            }
            return target.path
        } catch (error: Exception) {
            target.delete()
            throw error
        }
    }

    private fun isBackupFile(file: File): Boolean =
        file.isFile && isBackupName(file.name)

    private fun isBackupName(name: String): Boolean {
        val lower = name.lowercase()
        return lower.endsWith(".zip") || lower.endsWith(".json")
    }

    private fun sanitizeFileName(raw: String): String {
        val cleaned = raw.replace(Regex("""[\\/:*?"<>|\u0000-\u001F]"""), "_")
            .trim()
            .take(200)
        return cleaned.ifEmpty { "夜深导出文件" }
    }

    private fun runAsync(
        result: MethodChannel.Result,
        block: () -> Any?
    ) {
        executor.execute {
            try {
                val value = block()
                activity.runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error(
                        "storage_error",
                        error.message ?: "文件目录操作失败。",
                        null
                    )
                }
            }
        }
    }

    private data class SourceFile(
        val file: File,
        val displayName: String,
        val mimeType: String
    )

    private companion object {
        const val REQUEST_CODE_CHOOSE_DIRECTORY = 7320
        const val KEY_TREE_URI = "tree_uri"
        const val DEFAULT_FOLDER = "夜深"
    }
}
