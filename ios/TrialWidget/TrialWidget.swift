// Add in Xcode: File ▸ New ▸ Target ▸ Widget Extension named "TrialWidget",
// replace its Swift file with this one, and enable App Group "group.com.lovefist.subtracker"
// on both Runner and TrialWidget targets.
import SwiftUI
import WidgetKit

struct Trial: Decodable, Identifiable {
    let name: String
    let ends_at: Double // ms since epoch
    let charge: String
    var id: String { name }
    var end: Date { Date(timeIntervalSince1970: ends_at / 1000) }
}

struct Entry: TimelineEntry {
    let date: Date
    let trials: [Trial]
}

struct Provider: TimelineProvider {
    func load() -> [Trial] {
        let raw = UserDefaults(suiteName: "group.com.lovefist.subtracker")?.string(forKey: "trials") ?? "[]"
        return (try? JSONDecoder().decode([Trial].self, from: Data(raw.utf8))) ?? []
    }
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, trials: [Trial(name: "Netflix", ends_at: Date.now.addingTimeInterval(86400).timeIntervalSince1970 * 1000, charge: "£10.99")])
    }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, trials: load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Text(timerInterval:) ticks on its own; refresh every 30 min to drop ended trials.
        completion(Timeline(entries: [Entry(date: .now, trials: load())], policy: .after(.now.addingTimeInterval(1800))))
    }
}

struct TrialWidgetView: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Expiring trials").font(.caption).foregroundStyle(.secondary)
            if entry.trials.isEmpty {
                Text("No trials ending soon").font(.subheadline)
            }
            ForEach(entry.trials.filter { $0.end > entry.date }) { t in
                HStack {
                    VStack(alignment: .leading) {
                        Text(t.name).font(.subheadline.bold()).lineLimit(1)
                        Text("then \(t.charge)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(timerInterval: entry.date...t.end, countsDown: true)
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.15), Color(red: 0.03, green: 0.04, blue: 0.07)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

@main
struct TrialWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TrialWidget", provider: Provider()) { TrialWidgetView(entry: $0) }
            .configurationDisplayName("Expiring Trials")
            .description("Countdown to your next free-trial charges.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
