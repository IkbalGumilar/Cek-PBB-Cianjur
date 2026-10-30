package id.cianjur.cekpbb.cek_pbb_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.os.Bundle
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Android Home Screen AppWidget untuk Menampilkan Grafik DHKP PBB Secara Dinamis.
 *
 * Mendukung:
 * - Siklus 5 Jenis Grafik (Realisasi Dusun %, Uang Masuk Dusun Rp, Donut Capaian vs Piutang,
 *   Porsi Kontribusi Dusun, Tren Bulanan Jan–Des)
 * - Skala & Ukuran Dinamis (Auto-scale Canvas saat widget di-resize oleh launcher HP)
 * - Tombol navigasi [‹] dan [›] langsung dari layar depan tanpa membuka aplikasi
 * - Ketuk gambar grafik untuk membuka aplikasi ke halaman grafik DHKP
 */
class DhkpGrafikWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_PREV_CHART = "id.cianjur.cekpbb.cek_pbb_app.ACTION_PREV_CHART"
        const val ACTION_NEXT_CHART = "id.cianjur.cekpbb.cek_pbb_app.ACTION_NEXT_CHART"

        const val PREFS_NAME = "dhkp_widget_prefs"
        const val KEY_CHART_INDEX = "widget_chart_index"
        const val KEY_DATA_JSON = "widget_data_json"

        const val TOTAL_CHARTS = 5

        private val CHART_TITLES = arrayOf(
            "REALISASI PER DUSUN (%)",
            "UANG MASUK PER DUSUN (RP)",
            "TOTAL: LUNAS VS PIUTANG",
            "KONTRIBUSI SUMBANGAN DUSUN",
            "TREN PENERIMAAN BULANAN (JAN–DES)"
        )

        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, DhkpGrafikWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            for (id in appWidgetIds) {
                updateWidget(context, appWidgetManager, id)
            }
        }

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            options: Bundle? = null
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val chartIndex = prefs.getInt(KEY_CHART_INDEX, 0).coerceIn(0, TOTAL_CHARTS - 1)
            val dataJsonStr = prefs.getString(KEY_DATA_JSON, null)

            val widgetOpts = options ?: appWidgetManager.getAppWidgetOptions(appWidgetId)
            val minWidthDp = widgetOpts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180)
            val minHeightDp = widgetOpts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)

            val density = context.resources.displayMetrics.density
            val widthPx = (minWidthDp * density).toInt().coerceIn(360, 1920)
            val heightPx = (minHeightDp * density).toInt().coerceIn(240, 1920)

            // Header kira-kira 36dp
            val headerHeightPx = (36 * density).toInt()
            val chartHeightPx = (heightPx - headerHeightPx).coerceAtLeast(180)

            val data = parseData(dataJsonStr)

            // Buat Bitmap grafik dengan Canvas 2D resolusi tinggi
            val chartBitmap = drawChart(context, widthPx, chartHeightPx, chartIndex, data, density)

            val views = RemoteViews(context.packageName, R.layout.dhkp_grafik_widget_layout)

            views.setTextViewText(R.id.widget_chart_title, CHART_TITLES[chartIndex])
            views.setTextViewText(R.id.widget_chart_page, "${chartIndex + 1}/$TOTAL_CHARTS")
            views.setImageViewBitmap(R.id.widget_chart_image, chartBitmap)

            // Tombol Sebelumnya
            val prevIntent = Intent(context, DhkpGrafikWidgetProvider::class.java).apply {
                action = ACTION_PREV_CHART
            }
            val prevPending = PendingIntent.getBroadcast(
                context, 100, prevIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.btn_prev_chart, prevPending)

            // Tombol Selanjutnya
            val nextIntent = Intent(context, DhkpGrafikWidgetProvider::class.java).apply {
                action = ACTION_NEXT_CHART
            }
            val nextPending = PendingIntent.getBroadcast(
                context, 101, nextIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.btn_next_chart, nextPending)

            // Ketuk Gambar / Widget -> Buka Aplikasi
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("route", "/grafik")
            }
            val launchPending = PendingIntent.getActivity(
                context, 102, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_chart_image, launchPending)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun parseData(jsonStr: String?): WidgetData {
            if (jsonStr.isNullOrBlank()) {
                return defaultSampleData()
            }
            return try {
                val root = JSONObject(jsonStr)
                val totalNominal = root.optLong("totalNominal", 0L)
                val lunasNominal = root.optLong("lunasNominal", 0L)
                val belumBayarNominal = root.optLong("belumBayarNominal", 0L)
                val totalNop = root.optInt("totalNop", 0)
                val lunasNop = root.optInt("lunasNop", 0)
                val lunasPct = root.optDouble("lunasPct", 0.0)

                val dusuns = mutableListOf<DusunItem>()
                val dusunArr = root.optJSONArray("dusuns") ?: JSONArray()
                for (i in 0 until dusunArr.length()) {
                    val dObj = dusunArr.getJSONObject(i)
                    dusuns.add(
                        DusunItem(
                            name = dObj.optString("name", "Dusun ${i + 1}"),
                            targetRp = dObj.optLong("targetRp", 0L),
                            lunasRp = dObj.optLong("lunasRp", 0L),
                            lunasPct = dObj.optDouble("lunasPct", 0.0),
                            lunasNop = dObj.optInt("lunasNop", 0),
                            totalNop = dObj.optInt("totalNop", 0)
                        )
                    )
                }

                val months = mutableListOf<MonthItem>()
                val monthArr = root.optJSONArray("months") ?: JSONArray()
                val monthNames = arrayOf("Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Ags", "Sep", "Okt", "Nov", "Des")
                for (i in 0 until 12) {
                    if (i < monthArr.length()) {
                        val mObj = monthArr.getJSONObject(i)
                        months.add(
                            MonthItem(
                                month = mObj.optString("month", monthNames[i]),
                                nominal = mObj.optLong("nominal", 0L),
                                count = mObj.optInt("count", 0)
                            )
                        )
                    } else {
                        months.add(MonthItem(month = monthNames[i], nominal = 0L, count = 0))
                    }
                }

                WidgetData(
                    totalNominal = totalNominal,
                    lunasNominal = lunasNominal,
                    belumBayarNominal = belumBayarNominal,
                    totalNop = totalNop,
                    lunasNop = lunasNop,
                    lunasPct = lunasPct,
                    dusuns = if (dusuns.isNotEmpty()) dusuns else defaultSampleData().dusuns,
                    months = if (months.isNotEmpty()) months else defaultSampleData().months
                )
            } catch (e: Exception) {
                defaultSampleData()
            }
        }

        private fun defaultSampleData(): WidgetData {
            val sampleDusuns = listOf(
                DusunItem("Dusun 1", 35000000L, 29750000L, 85.0, 170, 200),
                DusunItem("Dusun 2", 28000000L, 19600000L, 70.0, 112, 160),
                DusunItem("Dusun 3", 42000000L, 22680000L, 54.0, 135, 250),
                DusunItem("Dusun 4", 30000000L, 11400000L, 38.0, 76, 200)
            )
            val monthNames = arrayOf("Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Ags", "Sep", "Okt", "Nov", "Des")
            val sampleMonths = monthNames.mapIndexed { idx, m ->
                val nom = when (idx) {
                    0 -> 4000000L
                    1 -> 8000000L
                    2 -> 14000000L
                    3 -> 9000000L
                    4 -> 16000000L
                    5 -> 22000000L
                    6 -> 18000000L
                    7 -> 28000000L
                    8 -> 34000000L
                    9 -> 12000000L
                    10 -> 7000000L
                    else -> 3000000L
                }
                MonthItem(m, nom, (nom / 150000).toInt())
            }
            return WidgetData(
                totalNominal = 135000000L,
                lunasNominal = 83430000L,
                belumBayarNominal = 51570000L,
                totalNop = 810,
                lunasNop = 493,
                lunasPct = 61.8,
                dusuns = sampleDusuns,
                months = sampleMonths
            )
        }

        fun formatRupiahShort(amount: Long): String {
            return when {
                amount >= 1000000000L -> String.format("%.1f M", amount / 1000000000.0)
                amount >= 1000000L -> String.format("%.1f Jt", amount / 1000000.0)
                amount >= 1000L -> String.format("%.0f Rb", amount / 1000.0)
                else -> amount.toString()
            }
        }

        private fun drawChart(
            context: Context,
            width: Int,
            height: Int,
            chartIndex: Int,
            data: WidgetData,
            density: Float
        ): Bitmap {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)

            when (chartIndex) {
                0 -> drawDusunPercentageChart(canvas, width, height, data, density)
                1 -> drawDusunRevenueChart(canvas, width, height, data, density)
                2 -> drawDonutTotalRealization(canvas, width, height, data, density)
                3 -> drawPieDusunContribution(canvas, width, height, data, density)
                4 -> drawMonthlyTrendCurve(canvas, width, height, data, density)
                else -> drawDusunPercentageChart(canvas, width, height, data, density)
            }

            return bitmap
        }

        // =====================================================================
        // 1. CHART 0: PERSENTASE CAPAIAN PER DUSUN (%)
        // =====================================================================
        private fun drawDusunPercentageChart(
            canvas: Canvas,
            width: Int,
            height: Int,
            data: WidgetData,
            density: Float
        ) {
            val items = data.dusuns
            if (items.isEmpty()) return

            val paddingH = 16f * density
            val paddingV = 10f * density
            val availableW = width - (paddingH * 2)
            val availableH = height - (paddingV * 2)

            val rowCount = items.size
            val rowHeight = availableH / rowCount

            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = (11f * density).coerceIn(18f, 32f)
                isFakeBoldText = true
            }
            val subTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#94A3B8")
                textSize = (9.5f * density).coerceIn(16f, 26f)
            }

            val labelWidth = min(availableW * 0.28f, 75f * density)
            val valueWidth = min(availableW * 0.22f, 65f * density)
            val barWidth = availableW - labelWidth - valueWidth - (12f * density)

            val barTrackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#1E293B")
                style = Paint.Style.FILL
            }

            for (i in 0 until rowCount) {
                val item = items[i]
                val topY = paddingV + (i * rowHeight)
                val centerY = topY + (rowHeight / 2)

                // Label Dusun
                canvas.drawText(item.name, paddingH, centerY + (4f * density), textPaint)

                // Track Latar Belakang Batang
                val barLeft = paddingH + labelWidth + (6f * density)
                val barRight = barLeft + barWidth
                val barH = (12f * density).coerceAtMost(rowHeight * 0.45f)
                val barTop = centerY - (barH / 2)
                val barBottom = centerY + (barH / 2)
                val radius = barH / 2

                val trackRect = RectF(barLeft, barTop, barRight, barBottom)
                canvas.drawRoundRect(trackRect, radius, radius, barTrackPaint)

                // Isi Batang Berdasarkan Persentase
                val fillRatio = (item.lunasPct / 100.0).coerceIn(0.0, 1.0).toFloat()
                val fillW = max(radius * 2, barWidth * fillRatio)

                val (cStart, cEnd) = when {
                    item.lunasPct >= 75.0 -> Pair(Color.parseColor("#10B981"), Color.parseColor("#059669")) // Hijau
                    item.lunasPct >= 50.0 -> Pair(Color.parseColor("#06B6D4"), Color.parseColor("#0891B2")) // Sian
                    item.lunasPct >= 25.0 -> Pair(Color.parseColor("#F59E0B"), Color.parseColor("#D97706")) // Amber
                    else -> Pair(Color.parseColor("#EF4444"), Color.parseColor("#DC2626")) // Merah
                }

                val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    shader = LinearGradient(
                        barLeft, barTop, barLeft + fillW, barTop,
                        cStart, cEnd, Shader.TileMode.CLAMP
                    )
                }
                val fillRect = RectF(barLeft, barTop, barLeft + fillW, barBottom)
                canvas.drawRoundRect(fillRect, radius, radius, fillPaint)

                // Teks Angka Persentase di Kanan
                val pctStr = String.format("%.1f%%", item.lunasPct)
                canvas.drawText(pctStr, barRight + (8f * density), centerY + (4f * density), textPaint)
            }
        }

        // =====================================================================
        // 2. CHART 1: UANG MASUK PER DUSUN (RP)
        // =====================================================================
        private fun drawDusunRevenueChart(
            canvas: Canvas,
            width: Int,
            height: Int,
            data: WidgetData,
            density: Float
        ) {
            val items = data.dusuns
            if (items.isEmpty()) return

            val paddingH = 16f * density
            val paddingV = 10f * density
            val availableW = width - (paddingH * 2)
            val availableH = height - (paddingV * 2)

            val maxNominal = items.map { it.targetRp }.maxOrNull()?.coerceAtLeast(1L) ?: 1L

            val isHorizontal = height < width * 0.65f || items.size <= 5

            if (isHorizontal) {
                // Layout Batang Mendatar yang Kaya Data
                val rowHeight = availableH / items.size
                val labelWidth = min(availableW * 0.26f, 75f * density)
                val valueWidth = min(availableW * 0.28f, 85f * density)
                val barWidth = availableW - labelWidth - valueWidth - (12f * density)

                val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.WHITE
                    textSize = (11f * density).coerceIn(18f, 32f)
                    isFakeBoldText = true
                }
                val subPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.parseColor("#94A3B8")
                    textSize = (9f * density).coerceIn(15f, 24f)
                }
                val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.parseColor("#1E293B")
                }

                for (i in items.indices) {
                    val item = items[i]
                    val topY = paddingV + (i * rowHeight)
                    val centerY = topY + (rowHeight / 2)

                    canvas.drawText(item.name, paddingH, centerY + (4f * density), textPaint)

                    val barLeft = paddingH + labelWidth + (6f * density)
                    val barRight = barLeft + barWidth
                    val barH = (14f * density).coerceAtMost(rowHeight * 0.5f)
                    val barTop = centerY - (barH / 2)
                    val barBottom = centerY + (barH / 2)
                    val radius = barH / 2

                    canvas.drawRoundRect(RectF(barLeft, barTop, barRight, barBottom), radius, radius, trackPaint)

                    val ratio = (item.lunasRp.toDouble() / maxNominal).coerceIn(0.0, 1.0).toFloat()
                    val fillW = max(radius * 2, barWidth * ratio)

                    val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        shader = LinearGradient(
                            barLeft, barTop, barLeft + fillW, barTop,
                            Color.parseColor("#14B8A6"), Color.parseColor("#0F766E"), Shader.TileMode.CLAMP
                        )
                    }
                    canvas.drawRoundRect(RectF(barLeft, barTop, barLeft + fillW, barBottom), radius, radius, fillPaint)

                    val rpStr = formatRupiahShort(item.lunasRp)
                    canvas.drawText(rpStr, barRight + (8f * density), centerY + (4f * density), textPaint)
                }
            } else {
                // Layout Batang Tegak (Column Bars)
                val bottomAxisH = 22f * density
                val chartH = availableH - bottomAxisH
                val colW = availableW / items.size

                val barWidth = (colW * 0.45f).coerceIn(16f * density, 40f * density)

                val colPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    shader = LinearGradient(
                        0f, paddingV, 0f, paddingV + chartH,
                        Color.parseColor("#14B8A6"), Color.parseColor("#0F766E"), Shader.TileMode.CLAMP
                    )
                }
                val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.WHITE
                    textSize = (10f * density).coerceIn(16f, 26f)
                    textAlign = Paint.Align.CENTER
                }
                val subPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.parseColor("#94A3B8")
                    textSize = (8.5f * density).coerceIn(14f, 22f)
                    textAlign = Paint.Align.CENTER
                }

                for (i in items.indices) {
                    val item = items[i]
                    val colCenterX = paddingH + (i * colW) + (colW / 2)
                    val barRatio = (item.lunasRp.toDouble() / maxNominal).coerceIn(0.0, 1.0).toFloat()
                    val barH = max(6f * density, chartH * barRatio)
                    val barTop = paddingV + chartH - barH
                    val barBottom = paddingV + chartH

                    val barRect = RectF(colCenterX - barWidth / 2, barTop, colCenterX + barWidth / 2, barBottom)
                    canvas.drawRoundRect(barRect, 6f * density, 6f * density, colPaint)

                    canvas.drawText(formatRupiahShort(item.lunasRp), colCenterX, barTop - (4f * density), subPaint)
                    canvas.drawText(item.name, colCenterX, paddingV + chartH + (16f * density), textPaint)
                }
            }
        }

        // =====================================================================
        // 3. CHART 2: DONUT TOTAL REALISASI (LUNAS VS PIUTANG)
        // =====================================================================
        private fun drawDonutTotalRealization(
            canvas: Canvas,
            width: Int,
            height: Int,
            data: WidgetData,
            density: Float
        ) {
            val paddingH = 16f * density
            val paddingV = 10f * density

            val chartSize = min(width * 0.45f, (height - paddingV * 2)).coerceAtLeast(100f * density)
            val donutCenterX = paddingH + (chartSize / 2)
            val donutCenterY = height / 2f
            val radius = (chartSize / 2) - (8f * density)
            val strokeW = (chartSize * 0.16f).coerceIn(14f * density, 32f * density)

            val safePct = data.lunasPct.coerceIn(0.0, 100.0).toFloat()
            val lunasSweep = (safePct / 100f) * 360f
            val sisaSweep = 360f - lunasSweep

            val donutRect = RectF(
                donutCenterX - radius,
                donutCenterY - radius,
                donutCenterX + radius,
                donutCenterY + radius
            )

            // Sisa Piutang Arc (Merah/Oranye)
            val piutangPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#F97316")
                style = Paint.Style.STROKE
                strokeWidth = strokeW
                strokeCap = Paint.Cap.BUTT
            }
            canvas.drawArc(donutRect, -90f + lunasSweep, sisaSweep, false, piutangPaint)

            // Lunas Arc (Hijau Zamrud)
            val lunasPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#10B981")
                style = Paint.Style.STROKE
                strokeWidth = strokeW + (2f * density)
                strokeCap = Paint.Cap.ROUND
            }
            if (lunasSweep > 0) {
                canvas.drawArc(donutRect, -90f, lunasSweep, false, lunasPaint)
            }

            // Teks Tengah Donut
            val centerTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = (chartSize * 0.22f).coerceIn(20f, 44f)
                isFakeBoldText = true
                textAlign = Paint.Align.CENTER
            }
            val centerSubPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#10B981")
                textSize = (chartSize * 0.12f).coerceIn(14f, 26f)
                isFakeBoldText = true
                textAlign = Paint.Align.CENTER
            }

            canvas.drawText(String.format("%.1f%%", safePct), donutCenterX, donutCenterY + (3f * density), centerTextPaint)
            canvas.drawText("LUNAS", donutCenterX, donutCenterY + (20f * density), centerSubPaint)

            // Legenda Sisi Kanan
            val legendLeft = donutCenterX + radius + (20f * density)
            val legendCenterY = height / 2f

            val legendTitlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = (12f * density).coerceIn(20f, 32f)
                isFakeBoldText = true
            }
            val legendSubPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#94A3B8")
                textSize = (10f * density).coerceIn(16f, 26f)
            }
            val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG)

            // Baris 1: Lunas
            val row1Y = legendCenterY - (18f * density)
            dotPaint.color = Color.parseColor("#10B981")
            canvas.drawCircle(legendLeft + (5f * density), row1Y - (4f * density), 5f * density, dotPaint)
            canvas.drawText("Lunas: ${formatRupiahShort(data.lunasNominal)}", legendLeft + (16f * density), row1Y, legendTitlePaint)
            canvas.drawText("${data.lunasNop} Objek Pajak (${String.format("%.1f%%", safePct)})", legendLeft + (16f * density), row1Y + (14f * density), legendSubPaint)

            // Baris 2: Piutang
            val row2Y = legendCenterY + (24f * density)
            dotPaint.color = Color.parseColor("#F97316")
            canvas.drawCircle(legendLeft + (5f * density), row2Y - (4f * density), 5f * density, dotPaint)
            canvas.drawText("Piutang: ${formatRupiahShort(data.belumBayarNominal)}", legendLeft + (16f * density), row2Y, legendTitlePaint)
            val sisaNop = max(0, data.totalNop - data.lunasNop)
            canvas.drawText("$sisaNop Objek Belum Bayar", legendLeft + (16f * density), row2Y + (14f * density), legendSubPaint)
        }

        // =====================================================================
        // 4. CHART 3: PORSI KONTRIBUSI DUSUN (PIE MULTI-SLICE)
        // =====================================================================
        private fun drawPieDusunContribution(
            canvas: Canvas,
            width: Int,
            height: Int,
            data: WidgetData,
            density: Float
        ) {
            val items = data.dusuns
            if (items.isEmpty()) return

            val paddingH = 16f * density
            val paddingV = 10f * density

            val chartSize = min(width * 0.44f, (height - paddingV * 2)).coerceAtLeast(100f * density)
            val pieCenterX = paddingH + (chartSize / 2)
            val pieCenterY = height / 2f
            val radius = (chartSize / 2) - (6f * density)
            val strokeW = (chartSize * 0.20f).coerceIn(16f * density, 34f * density)

            val totalLunas = items.map { it.lunasRp }.sum().coerceAtLeast(1L)
            val sliceColors = arrayOf(
                Color.parseColor("#10B981"), // Hijau Emerald
                Color.parseColor("#06B6D4"), // Biru Cyan
                Color.parseColor("#8B5CF6"), // Ungu Violet
                Color.parseColor("#F59E0B"), // Amber
                Color.parseColor("#EC4899"), // Pink
                Color.parseColor("#3B82F6")  // Biru
            )

            val pieRect = RectF(
                pieCenterX - radius,
                pieCenterY - radius,
                pieCenterX + radius,
                pieCenterY + radius
            )

            var startAngle = -90f
            val slicePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = strokeW
                strokeCap = Paint.Cap.BUTT
            }

            for (i in items.indices) {
                val item = items[i]
                val sweep = (item.lunasRp.toFloat() / totalLunas) * 360f
                slicePaint.color = sliceColors[i % sliceColors.size]
                canvas.drawArc(pieRect, startAngle, sweep, false, slicePaint)
                startAngle += sweep
            }

            // Label Total di Tengah Donut
            val centerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = (chartSize * 0.16f).coerceIn(16f, 32f)
                isFakeBoldText = true
                textAlign = Paint.Align.CENTER
            }
            val subPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#94A3B8")
                textSize = (chartSize * 0.10f).coerceIn(12f, 22f)
                textAlign = Paint.Align.CENTER
            }
            canvas.drawText(formatRupiahShort(totalLunas), pieCenterX, pieCenterY + (2f * density), centerPaint)
            canvas.drawText("TERKUMPUL", pieCenterX, pieCenterY + (16f * density), subPaint)

            // Legenda di Kanan
            val legendLeft = pieCenterX + radius + (18f * density)
            val availableLegW = width - legendLeft - paddingH
            val rowH = min(22f * density, (height - paddingV * 2) / items.size)
            val startY = (height / 2f) - ((items.size * rowH) / 2) + (rowH / 2)

            val legTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = (10f * density).coerceIn(16f, 26f)
            }
            val legPctPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#38BDF8")
                textSize = (10f * density).coerceIn(16f, 26f)
                isFakeBoldText = true
            }
            val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG)

            for (i in items.indices) {
                val item = items[i]
                val y = startY + (i * rowH)
                val pct = (item.lunasRp.toDouble() / totalLunas * 100.0)

                dotPaint.color = sliceColors[i % sliceColors.size]
                canvas.drawCircle(legendLeft + (5f * density), y - (3f * density), 4.5f * density, dotPaint)
                canvas.drawText(item.name, legendLeft + (14f * density), y, legTextPaint)

                val pctStr = String.format("%.1f%%", pct)
                canvas.drawText(pctStr, legendLeft + (14f * density) + (availableLegW * 0.55f), y, legPctPaint)
            }
        }

        // =====================================================================
        // 5. CHART 4: TREN PENERIMAAN BULANAN (JAN–DES LINE AREA)
        // =====================================================================
        private fun drawMonthlyTrendCurve(
            canvas: Canvas,
            width: Int,
            height: Int,
            data: WidgetData,
            density: Float
        ) {
            val months = data.months
            if (months.isEmpty()) return

            val paddingH = 20f * density
            val paddingV = 14f * density
            val axisBottomH = 20f * density

            val chartW = width - (paddingH * 2)
            val chartH = height - (paddingV * 2) - axisBottomH

            val maxVal = months.map { it.nominal }.maxOrNull()?.coerceAtLeast(1L) ?: 1L

            val stepX = chartW / (months.size - 1)
            val points = mutableListOf<Pair<Float, Float>>()

            for (i in months.indices) {
                val x = paddingH + (i * stepX)
                val ratio = (months[i].nominal.toDouble() / maxVal).coerceIn(0.0, 1.0).toFloat()
                val y = paddingV + chartH - (ratio * chartH * 0.88f)
                points.add(Pair(x, y))
            }

            // Garis Kisi Tipis Horizontal
            val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#1E293B")
                strokeWidth = 1f * density
            }
            for (g in 1..3) {
                val gy = paddingV + (chartH * (g / 4f))
                canvas.drawLine(paddingH, gy, paddingH + chartW, gy, gridPaint)
            }

            // Jalur Kurva Halus (Cubic Bezier Path)
            val path = Path().apply {
                moveTo(points[0].first, points[0].second)
                for (i in 0 until points.size - 1) {
                    val p0 = points[i]
                    val p1 = points[i + 1]
                    val cpX = (p0.first + p1.first) / 2
                    cubicTo(cpX, p0.second, cpX, p1.second, p1.first, p1.second)
                }
            }

            // Isi Gradasi Area Bawah Kurva
            val fillPath = Path(path).apply {
                lineTo(points.last().first, paddingV + chartH)
                lineTo(points.first().first, paddingV + chartH)
                close()
            }
            val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = LinearGradient(
                    0f, paddingV, 0f, paddingV + chartH,
                    Color.parseColor("#9333EA").apply { /* Alpha ~0.45 */ },
                    Color.TRANSPARENT,
                    Shader.TileMode.CLAMP
                )
                style = Paint.Style.FILL
            }
            canvas.drawPath(fillPath, fillPaint)

            // Garis Kurva Utama
            val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#A855F7")
                style = Paint.Style.STROKE
                strokeWidth = 3f * density
                strokeCap = Paint.Cap.ROUND
            }
            canvas.drawPath(path, strokePaint)

            // Titik Bulan & Teks Axis Bawah
            val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#C084FC")
            }
            val dotInner = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#0F172A")
            }
            val monthTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#94A3B8")
                textSize = (8.5f * density).coerceIn(14f, 22f)
                textAlign = Paint.Align.CENTER
            }

            // Cari bulan puncak untuk diberi label angka
            var maxIdx = 0
            for (i in months.indices) {
                if (months[i].nominal > months[maxIdx].nominal) maxIdx = i
            }

            val peakTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#FDE047")
                textSize = (9f * density).coerceIn(14f, 24f)
                isFakeBoldText = true
                textAlign = Paint.Align.CENTER
            }

            for (i in points.indices) {
                val p = points[i]
                val isPeak = i == maxIdx && months[i].nominal > 0

                val radiusOuter = if (isPeak) 5f * density else 3.5f * density
                val radiusInner = if (isPeak) 2.5f * density else 1.8f * density

                canvas.drawCircle(p.first, p.second, radiusOuter, if (isPeak) Paint().apply { color = Color.parseColor("#FDE047") } else dotPaint)
                canvas.drawCircle(p.first, p.second, radiusInner, dotInner)

                // Label Bulan Bawah
                canvas.drawText(months[i].month, p.first, paddingV + chartH + (14f * density), monthTextPaint)

                // Label Puncak Uang Masuk
                if (isPeak) {
                    canvas.drawText(formatRupiahShort(months[i].nominal), p.first, p.second - (8f * density), peakTextPaint)
                }
            }
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?
    ) {
        // Dinamis Auto-Scale Canvas saat ukuran widget diubah di launcher
        updateWidget(context, appWidgetManager, appWidgetId, newOptions)
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action ?: return

        if (action == ACTION_NEXT_CHART) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val current = prefs.getInt(KEY_CHART_INDEX, 0)
            val next = (current + 1) % TOTAL_CHARTS
            prefs.edit().putInt(KEY_CHART_INDEX, next).apply()
            updateAllWidgets(context)
        } else if (action == ACTION_PREV_CHART) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val current = prefs.getInt(KEY_CHART_INDEX, 0)
            val prev = if (current - 1 < 0) TOTAL_CHARTS - 1 else current - 1
            prefs.edit().putInt(KEY_CHART_INDEX, prev).apply()
            updateAllWidgets(context)
        }
    }
}

data class DusunItem(
    val name: String,
    val targetRp: Long,
    val lunasRp: Long,
    val lunasPct: Double,
    val lunasNop: Int,
    val totalNop: Int
)

data class MonthItem(
    val month: String,
    val nominal: Long,
    val count: Int
)

data class WidgetData(
    val totalNominal: Long,
    val lunasNominal: Long,
    val belumBayarNominal: Long,
    val totalNop: Int,
    val lunasNop: Int,
    val lunasPct: Double,
    val dusuns: List<DusunItem>,
    val months: List<MonthItem>
)
