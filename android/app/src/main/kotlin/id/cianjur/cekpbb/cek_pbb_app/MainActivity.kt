package id.cianjur.cekpbb.cek_pbb_app

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    private val apkChannelName = "id.cianjur.cekpbb.cek_pbb_app/apk"
    private val filesChannelName = "id.cianjur.cekpbb.cek_pbb_app/files"
    private val bankChannelName = "id.cianjur.cekpbb.cek_pbb_app/bank"

    // Nama folder publik tempat semua dokumen aplikasi ini disimpan:
    // Dokumen/Cek PBB Cianjur (hasil cek, bukti bayar, laporan blok, backup).
    private val documentsFolderName = "Cek PBB Cianjur"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, apkChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportApk" -> exportApk(result)
                "shareApk" -> shareApk(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, filesChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDocuments" -> saveToDocuments(call, result)
                "shareBytes" -> shareBytes(call, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bankChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkInstalledApps" -> checkInstalledApps(call, result)
                "launchApp" -> launchApp(call, result)
                "getAppIcon" -> getAppIcon(call, result)
                else -> result.notImplemented()
            }
        }
    }

    // Ambil ikon asli aplikasi yang terpasang (bukan aset logo yang kita
    // bundel sendiri) supaya selalu akurat dan tidak perlu urus hak cipta
    // logo brand pihak ketiga.
    private fun getAppIcon(call: MethodCall, result: MethodChannel.Result) {
        try {
            val packageName = call.argument<String>("packageName")!!
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = drawableToBitmap(drawable)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            result.success(stream.toByteArray())
        } catch (e: Exception) {
            result.error("ICON_FAILED", e.message, null)
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable) return drawable.bitmap
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 108
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 108
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    // Dari daftar kandidat package name aplikasi bank/e-wallet, balikin yang
    // benar-benar terpasang di perangkat ini. Package yang salah tebak/tidak
    // terpasang otomatis gugur di sini (bukan error), jadi aman dari daftar
    // kandidat yang belum tentu semuanya akurat.
    private fun checkInstalledApps(call: MethodCall, result: MethodChannel.Result) {
        try {
            val packageNames = call.argument<List<String>>("packageNames") ?: emptyList()
            val installed = packageNames.filter { packageManager.getLaunchIntentForPackage(it) != null }
            result.success(installed)
        } catch (e: Exception) {
            result.error("CHECK_FAILED", e.message, null)
        }
    }

    // Buka aplikasi bank/e-wallet lain langsung ke layar utamanya. Tidak ada
    // cara resmi untuk mengisi otomatis nomor Virtual Account di aplikasi
    // pihak ketiga (setiap bank punya sistem sendiri, tidak ada standar
    // publik untuk itu) — jadi nomor VA sudah disalin ke clipboard sebelum
    // ini dipanggil, dan user tinggal tempel begitu aplikasi banknya kebuka.
    private fun launchApp(call: MethodCall, result: MethodChannel.Result) {
        try {
            val packageName = call.argument<String>("packageName")!!
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent == null) {
                result.success(false)
                return
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, null)
        }
    }

    private fun exportedFile(): File {
        val source = File(applicationInfo.sourceDir)
        val dest = File(cacheDir, "CekPBBCianjur.apk")
        source.copyTo(dest, overwrite = true)
        return dest
    }

    private fun exportApk(result: MethodChannel.Result) {
        try {
            result.success(exportedFile().absolutePath)
        } catch (e: Exception) {
            result.error("EXPORT_FAILED", e.message, null)
        }
    }

    // Membuka share sheet Android langsung lewat Intent native, bukan lewat
    // share_plus: share_plus menunggu user memilih aplikasi tujuan sebelum
    // hasilnya dikembalikan ke Dart (withResult), dan kalau share() dipanggil
    // lagi sebelum pilihan itu dibuat, panggilan sebelumnya "dipaksa selesai"
    // begitu saja tanpa share sheet pernah tampil. Di sini kita langsung
    // startActivity tanpa menunggu, supaya tidak tergantung interaksi user.
    private fun shareApk(result: MethodChannel.Result) {
        try {
            val file = exportedFile()
            val uri = FileProvider.getUriForFile(this, "$packageName.apkprovider", file)
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "application/vnd.android.package-archive"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(
                    Intent.EXTRA_TEXT,
                    "Aplikasi Cek PBB Cianjur (install manual, tidak tersedia di Play Store)"
                )
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val chooser = Intent.createChooser(shareIntent, "Bagikan Aplikasi").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            result.success(null)
        } catch (e: Exception) {
            result.error("SHARE_FAILED", e.message, null)
        }
    }

    // Cari entri MediaStore yang sudah ada dengan nama+lokasi sama, supaya file
    // dengan nama tetap (mis. backup harian) ditimpa bukan diduplikasi dengan
    // akhiran "(1)".
    private fun findExistingDocument(relativePath: String, fileName: String): android.net.Uri? {
        val collection = MediaStore.Files.getContentUri("external")
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
        val args = arrayOf(fileName, relativePath)
        contentResolver.query(collection, projection, selection, args, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
                return ContentUris.withAppendedId(collection, id)
            }
        }
        return null
    }

    // Simpan bytes ke folder publik Dokumen/Cek PBB Cianjur. Tidak lewat
    // media_store_plus lagi: plugin itu menyerialisasi hasilnya lewat Gson di
    // sisi native, dan R8 di build release mengacak nama field Kotlin-nya
    // (jadi "name" jadi "a", dst) sehingga parsing manual di sisi Dart gagal
    // diam-diam. Ditulis native di sini supaya kita kontrol penuh formatnya.
    private fun saveToDocuments(call: MethodCall, result: MethodChannel.Result) {
        try {
            val fileName = call.argument<String>("fileName")!!
            val bytes = call.argument<ByteArray>("bytes")!!
            val mimeType = call.argument<String>("mimeType")!!

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val relativePath = "${Environment.DIRECTORY_DOCUMENTS}/$documentsFolderName/"
                findExistingDocument(relativePath, fileName)?.let { contentResolver.delete(it, null, null) }

                val contentValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                }
                val uri = contentResolver.insert(MediaStore.Files.getContentUri("external"), contentValues)
                    ?: throw Exception("Gagal membuat entri berkas di MediaStore.")
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw Exception("Gagal membuka aliran tulis berkas.")
            } else {
                @Suppress("DEPRECATION")
                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS), documentsFolderName)
                dir.mkdirs()
                File(dir, fileName).writeBytes(bytes)
            }
            result.success("Dokumen/$documentsFolderName/$fileName")
        } catch (e: Exception) {
            result.error("SAVE_FAILED", e.message, null)
        }
    }

    // Bagikan bytes langsung lewat share sheet Android (sama seperti shareApk,
    // tapi generik untuk berkas apa pun: CSV, XLSX, PDF).
    private fun shareBytes(call: MethodCall, result: MethodChannel.Result) {
        try {
            val fileName = call.argument<String>("fileName")!!
            val bytes = call.argument<ByteArray>("bytes")!!
            val mimeType = call.argument<String>("mimeType")!!

            val file = File(cacheDir, fileName)
            file.writeBytes(bytes)
            val uri = FileProvider.getUriForFile(this, "$packageName.apkprovider", file)
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val chooser = Intent.createChooser(shareIntent, "Bagikan Berkas").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            result.success(null)
        } catch (e: Exception) {
            result.error("SHARE_FAILED", e.message, null)
        }
    }
}
