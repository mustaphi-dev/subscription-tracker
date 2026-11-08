package app.trywince.wince

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import kotlin.concurrent.thread

/**
 * "Upcoming Charges" widget: next trials and subscription renewals, each logo in a ring that fills
 * as the charge nears. Data written by lib/widget_sync.dart; mirrors ios/TrialWidget/TrialWidget.swift.
 */
class TrialWidgetProvider : HomeWidgetProvider() {
    private val accent = 0xFF8B7CFF.toInt()
    private val urgent = 0xFFFF5C6C.toInt()
    private val orange = 0xFFFF9F0A.toInt()

    private val rows = listOf(
        intArrayOf(R.id.row0, R.id.ring0, R.id.name0, R.id.label0, R.id.left0),
        intArrayOf(R.id.row1, R.id.ring1, R.id.name1, R.id.label1, R.id.left1),
        intArrayOf(R.id.row2, R.id.ring2, R.id.name2, R.id.label2, R.id.left2),
        intArrayOf(R.id.row3, R.id.ring3, R.id.name3, R.id.label3, R.id.left3),
        intArrayOf(R.id.row4, R.id.ring4, R.id.name4, R.id.label4, R.id.left4),
    )

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, prefs: SharedPreferences) {
        val now = System.currentTimeMillis()
        val all = JSONArray(prefs.getString("trials", "[]"))
        val items = (0 until all.length()).map { all.getJSONObject(it) }.filter { it.getLong("ends_at") > now }
        // Logos need the network, which a receiver can't use on the main thread.
        val pending = goAsync()
        thread {
            try {
                val logos = items.map { it.optString("logo").takeIf { s -> s.isNotEmpty() && s != "null" }?.let(::fetch) }
                for (id in ids) manager.updateAppWidget(id, build(context, manager, id, items, logos, now))
            } finally {
                pending.finish()
            }
        }
    }

    // Resizing changes how many rows fit.
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        onUpdate(context, manager, intArrayOf(id), HomeWidgetPlugin.getData(context))
    }

    private fun build(context: Context, manager: AppWidgetManager, id: Int, items: List<JSONObject>, logos: List<Bitmap?>, now: Long): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.trial_widget)
        views.setOnClickPendingIntent(R.id.root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
        views.setViewVisibility(R.id.empty, if (items.isEmpty()) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.count, if (items.isEmpty()) "" else "${items.size} upcoming")
        // Small (2-cell) widget: logo alone so the count fits. Blank rather than hide: the title is the spacer.
        val width = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
        views.setTextViewText(R.id.title, if (width < 180) "" else "Wince")
        // ~28dp padding + header, then ~42dp a row.
        val height = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 180)
        val fit = ((height - 50) / 42).coerceIn(1, rows.size)
        rows.forEachIndexed { i, (row, ring, name, label, left) ->
            if (i >= items.size || i >= fit) {
                views.setViewVisibility(row, View.GONE)
                return@forEachIndexed
            }
            val t = items[i]
            val end = t.getLong("ends_at")
            val ms = end - now
            val trial = t.optBoolean("trial", true)
            val charge = t.getString("charge")
            views.setViewVisibility(row, View.VISIBLE)
            views.setTextViewText(name, t.getString("name"))
            views.setTextViewText(label, if (trial) "Trial · then $charge" else "Renews · $charge")
            val start = if (t.isNull("starts_at")) null else t.getLong("starts_at")
            val progress = if (start == null || end <= start) 0f else ((now - start).toFloat() / (end - start)).coerceIn(0f, 1f)
            views.setImageViewBitmap(ring, ring(t.getString("name"), logos[i], progress, if (ms < 48 * 3600_000L) urgent else accent))
            val d = daysUntil(now, end)
            views.setTextViewText(left, if (d <= 0) "Today" else if (d == 1) "Tomorrow" else "In $d days")
            views.setTextColor(left, if (d <= 0) urgent else if (d == 1) orange else accent)
        }
        return views
    }

    /** Calendar days from today to [end]'s day: 0 today, 1 tomorrow. */
    private fun daysUntil(now: Long, end: Long): Int {
        fun midnight(t: Long) = Calendar.getInstance().apply {
            timeInMillis = t; set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        return Math.round((midnight(end) - midnight(now)) / 86_400_000.0).toInt() // round: DST days aren't 24h
    }

    private fun fetch(url: String): Bitmap? = try {
        (URL(url).openConnection() as HttpURLConnection).run {
            connectTimeout = 3000
            readTimeout = 3000
            if (responseCode == 200) inputStream.use(BitmapFactory::decodeStream) else null
        }
    } catch (_: Exception) {
        null
    }

    /** Circular logo (or letter tile) inside a progress ring, as one bitmap since RemoteViews can't draw. */
    private fun ring(name: String, logo: Bitmap?, progress: Float, tone: Int): Bitmap {
        val size = 102
        val stroke = 9f
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val arc = RectF(stroke / 2, stroke / 2, size - stroke / 2, size - stroke / 2)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = stroke; strokeCap = Paint.Cap.ROUND }
        c.drawArc(arc, 0f, 360f, false, p.apply { color = 0x14FFFFFF })
        if (progress > 0f) c.drawArc(arc, -90f, 360f * progress, false, p.apply { color = tone })
        val inner = RectF(stroke * 2, stroke * 2, size - stroke * 2, size - stroke * 2)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG)
        if (logo != null) {
            fill.shader = BitmapShader(logo, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
                val scale = maxOf(inner.width() / logo.width, inner.height() / logo.height)
                setLocalMatrix(Matrix().apply { setScale(scale, scale); postTranslate(inner.left, inner.top) })
            }
            c.drawOval(inner, fill)
        } else {
            c.drawOval(inner, fill.apply { color = (accent and 0x00FFFFFF) or 0x40000000 })
            val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFFFFFFFF.toInt(); textSize = inner.height() * 0.45f; textAlign = Paint.Align.CENTER; isFakeBoldText = true
            }
            c.drawText(name.take(1).uppercase(), inner.centerX(), inner.centerY() - (text.ascent() + text.descent()) / 2, text)
        }
        return out
    }
}
