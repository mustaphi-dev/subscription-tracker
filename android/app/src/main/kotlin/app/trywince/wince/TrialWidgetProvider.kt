package app.trywince.wince

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/** "Expiring Trials" home-screen widget. Data written by lib/push.dart → updateTrialWidget(). */
class TrialWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, prefs: SharedPreferences) {
        val trials = JSONArray(prefs.getString("trials", "[]"))
        val rows = listOf(
            Triple(R.id.name0, R.id.timer0, R.id.charge0),
            Triple(R.id.name1, R.id.timer1, R.id.charge1),
            Triple(R.id.name2, R.id.timer2, R.id.charge2),
        )
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.trial_widget)
            views.setViewVisibility(R.id.empty, if (trials.length() == 0) View.VISIBLE else View.GONE)
            rows.forEachIndexed { i, (name, timer, charge) ->
                val visible = i < trials.length()
                listOf(name, timer, charge).forEach { views.setViewVisibility(it, if (visible) View.VISIBLE else View.GONE) }
                if (!visible) return@forEachIndexed
                val t = trials.getJSONObject(i)
                views.setTextViewText(name, t.getString("name"))
                views.setTextViewText(charge, "then ${t.getString("charge")}")
                // Chronometer counts down natively, no app wake-ups needed.
                val base = SystemClock.elapsedRealtime() + (t.getLong("ends_at") - System.currentTimeMillis())
                views.setChronometer(timer, base, null, true)
                views.setChronometerCountDown(timer, true)
            }
            manager.updateAppWidget(id, views)
        }
    }
}
