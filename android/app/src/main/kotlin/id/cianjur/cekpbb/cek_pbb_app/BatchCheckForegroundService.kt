package id.cianjur.cekpbb.cek_pbb_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/// Layanan latar depan (Foreground Service) Android dengan tipe dataSync dan Partial WakeLock.
/// Mencegah Android 14/15 mematikan koneksi internet (socket) dan menidurkan CPU
/// saat pengguna beralih aplikasi atau mematikan layar HP ketika cek massal sedang berlangsung.
class BatchCheckForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "batch_check_fg_channel"
        const val CHANNEL_NAME = "Proses Pengecekan Massal PBB"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "ACTION_START"
        const val ACTION_UPDATE = "ACTION_UPDATE"
        const val ACTION_STOP = "ACTION_STOP"
        const val ACTION_PAUSE = "ACTION_PAUSE"
        const val ACTION_RESUME = "ACTION_RESUME"
        const val ACTION_HIDE = "ACTION_HIDE"
        const val ACTION_CANCEL = "ACTION_CANCEL"

        const val EXTRA_TITLE = "EXTRA_TITLE"
        const val EXTRA_CONTENT = "EXTRA_CONTENT"
        const val EXTRA_PROGRESS = "EXTRA_PROGRESS"
        const val EXTRA_MAX = "EXTRA_MAX"
        const val EXTRA_IS_PAUSED = "EXTRA_IS_PAUSED"

        var isRunning = false
            private set

        var isPaused = false
            private set

        var onActionReceived: ((String) -> Unit)? = null
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var lastTitle: String = "Pengecekan Massal PBB Berjalan"
    private var lastContent: String = "Memeriksa status pembayaran..."
    private var lastProgress: Int = 0
    private var lastMax: Int = 100

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Pengecekan Massal PBB Berjalan"
                val content = intent.getStringExtra(EXTRA_CONTENT) ?: "Memeriksa status pembayaran..."
                val progress = intent.getIntExtra(EXTRA_PROGRESS, 0)
                val max = intent.getIntExtra(EXTRA_MAX, 100)
                isPaused = intent.getBooleanExtra(EXTRA_IS_PAUSED, false)
                lastTitle = title
                lastContent = content
                lastProgress = progress
                lastMax = max
                startForegroundService(title, content, progress, max)
            }
            ACTION_UPDATE -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: lastTitle
                val content = intent.getStringExtra(EXTRA_CONTENT) ?: lastContent
                val progress = intent.getIntExtra(EXTRA_PROGRESS, lastProgress)
                val max = intent.getIntExtra(EXTRA_MAX, lastMax)
                if (intent.hasExtra(EXTRA_IS_PAUSED)) {
                    isPaused = intent.getBooleanExtra(EXTRA_IS_PAUSED, false)
                }
                lastTitle = title
                lastContent = content
                lastProgress = progress
                lastMax = max
                updateNotification(title, content, progress, max)
            }
            ACTION_STOP -> {
                stopForegroundService()
            }
            ACTION_PAUSE -> {
                isPaused = true
                updateNotification(lastTitle, lastContent, lastProgress, lastMax)
                onActionReceived?.invoke("pause")
            }
            ACTION_RESUME -> {
                isPaused = false
                updateNotification(lastTitle, lastContent, lastProgress, lastMax)
                onActionReceived?.invoke("resume")
            }
            ACTION_HIDE -> {
                closeNotificationDrawer()
                onActionReceived?.invoke("hide")
            }
            ACTION_CANCEL -> {
                onActionReceived?.invoke("cancel")
            }
        }
        return START_NOT_STICKY
    }

    private fun closeNotificationDrawer() {
        try {
            @Suppress("DEPRECATION")
            val it = Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
            sendBroadcast(it)
        } catch (_: Exception) {}
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Menjaga koneksi internet dan proses pengecekan massal tetap aktif di latar belakang"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, content: String, progress: Int, max: Int): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Tombol 1: Jeda atau Lanjutkan
        val pauseTitle = if (isPaused) "Lanjutkan" else "Jeda"
        val pauseAction = if (isPaused) ACTION_RESUME else ACTION_PAUSE
        val pauseIntent = Intent(this, BatchCheckForegroundService::class.java).apply {
            action = pauseAction
        }
        val pausePendingIntent = PendingIntent.getService(
            this,
            1,
            pauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Tombol 2: Sembunyikan
        val hideIntent = Intent(this, BatchCheckForegroundService::class.java).apply {
            action = ACTION_HIDE
        }
        val hidePendingIntent = PendingIntent.getService(
            this,
            2,
            hideIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Tombol 3: Batalkan
        val cancelIntent = Intent(this, BatchCheckForegroundService::class.java).apply {
            action = ACTION_CANCEL
        }
        val cancelPendingIntent = PendingIntent.getService(
            this,
            3,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val percent = if (max > 0) ((progress.toFloat() / max.toFloat()) * 100).toInt() else 0

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle(title)
            .setContentText(content)
            .setSubText("$percent%")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setColor(0xFF1565C0.toInt())
            .addAction(
                if (isPaused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
                pauseTitle,
                pausePendingIntent
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Sembunyikan",
                hidePendingIntent
            )
            .addAction(
                android.R.drawable.ic_menu_delete,
                "Batalkan",
                cancelPendingIntent
            )

        if (max > 0) {
            builder.setProgress(max, progress, false)
        }

        return builder.build()
    }

    private fun startForegroundService(title: String, content: String, progress: Int, max: Int) {
        isRunning = true
        acquireWakeLock()
        val notification = buildNotification(title, content, progress, max)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            }
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(title: String, content: String, progress: Int, max: Int) {
        if (!isRunning) return
        val notification = buildNotification(title, content, progress, max)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        manager?.notify(NOTIFICATION_ID, notification)
    }

    private fun stopForegroundService() {
        isRunning = false
        isPaused = false
        releaseWakeLock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = pm?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "CekPBBCianjur:BatchCheckWakeLock"
            )?.apply {
                setReferenceCounted(false)
                acquire(2 * 60 * 60 * 1000L) // maks 2 jam untuk batch besar
            }
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        wakeLock = null
    }

    override fun onDestroy() {
        stopForegroundService()
        super.onDestroy()
    }
}
