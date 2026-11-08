// Add in Xcode: File ▸ New ▸ Target ▸ Widget Extension named "TrialWidget",
// replace its Swift file with this one, and enable App Group "group.app.trywince.wince"
// on both Runner and TrialWidget targets.
import SwiftUI
import WidgetKit

struct Trial: Decodable, Identifiable {
    let name: String
    let ends_at: Double // ms since epoch
    let charge: String
    let logo: String? // logo.dev URL from the app; fetched at refresh since widget views can't load network images
    var starts_at: Double? = nil // trial added / last renewal, for the ring
    var trial: Bool? = nil // older app versions only sent trials
    var id: String { name }
    var end: Date { Date(timeIntervalSince1970: ends_at / 1000) }
    var isTrial: Bool { trial ?? true }
    var label: String { isTrial ? "Trial · then \(charge)" : "Renews · \(charge)" }
    /// Share of the period already gone, 0...1.
    func progress(_ now: Date) -> Double {
        guard let s = starts_at else { return 0 }
        let start = Date(timeIntervalSince1970: s / 1000), total = end.timeIntervalSince(start)
        return total <= 0 ? 1 : min(max(now.timeIntervalSince(start) / total, 0), 1)
    }
    /// Same rule as the app's Home ring: red inside 48 hours.
    func tone(_ now: Date) -> Color { end.timeIntervalSince(now) < 172800 ? kUrgent : kAccent }
}

struct Entry: TimelineEntry {
    let date: Date
    let trials: [Trial]
    var logos: [String: UIImage] = [:]
}

struct Provider: TimelineProvider {
    func load() -> [Trial] {
        let raw = UserDefaults(suiteName: "group.app.trywince.wince")?.string(forKey: "trials") ?? "[]"
        return (try? JSONDecoder().decode([Trial].self, from: Data(raw.utf8))) ?? []
    }
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, trials: [Trial(name: "Netflix", ends_at: Date.now.addingTimeInterval(86400).timeIntervalSince1970 * 1000, charge: "£10.99", logo: nil, starts_at: Date.now.addingTimeInterval(-6 * 86400).timeIntervalSince1970 * 1000)])
    }
    func entry() async -> Entry {
        let trials = load()
        var logos: [String: UIImage] = [:]
        for t in trials {
            guard let s = t.logo, let url = URL(string: s),
                  let (data, res) = try? await URLSession.shared.data(from: url),
                  (res as? HTTPURLResponse)?.statusCode == 200,
                  let img = UIImage(data: data) else { continue }
            logos[t.name] = img
        }
        return Entry(date: .now, trials: trials, logos: logos)
    }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        Task { completion(await entry()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Refresh every 30 min so day labels roll over and ended items drop off.
        Task { completion(Timeline(entries: [await entry()], policy: .after(.now.addingTimeInterval(1800)))) }
    }
}

// Brand colours from lib/ui.dart.
private let kBg = Color(red: 0.03, green: 0.03, blue: 0.05)
private let kGlow = Color(red: 0.35, green: 0.25, blue: 0.94)
private let kAccent = Color(red: 0.55, green: 0.49, blue: 1.0)
private let kMuted = Color(red: 0.55, green: 0.56, blue: 0.61)
private let kUrgent = Color(red: 1.0, green: 0.36, blue: 0.42) // kCrimson

/// Calendar days until the charge: "Today", "Tomorrow", "In 5 days".
struct Countdown: View {
    let end: Date, now: Date
    var body: some View {
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: end)).day ?? 0
        Text(d <= 0 ? "Today" : d == 1 ? "Tomorrow" : "In \(d) days")
            .foregroundStyle(d <= 0 ? kUrgent : d == 1 ? .orange : kAccent)
    }
}

struct Header: View {
    @Environment(\.widgetFamily) var family
    let count: Int
    var body: some View {
        HStack(spacing: 6) {
            Image("Logo").resizable().frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5))
            if family != .systemSmall { // small: logo alone so the count fits
                Text("Wince").font(.caption.bold()).foregroundStyle(.white)
            }
            Spacer()
            if count > 0 {
                Text("\(count) upcoming").font(.caption2.bold()).foregroundStyle(kAccent)
            }
        }
    }
}

/// Logo inside a ring that fills as the charge gets closer (like the app's Home trial cards).
struct RingLogo: View {
    let t: Trial, image: UIImage?, now: Date, size: CGFloat
    var body: some View {
        let w = size * 0.1
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: w)
            Circle().trim(from: 0, to: t.progress(now))
                .stroke(t.tone(now), style: StrokeStyle(lineWidth: w, lineCap: .round))
                .rotationEffect(.degrees(-90))
            TrialLogo(name: t.name, image: image, size: size - w * 4)
        }
        .frame(width: size, height: size)
    }
}

/// Merchant logo, or a letter tile when there's none (same fallback as the app).
struct TrialLogo: View {
    let name: String, image: UIImage?, size: CGFloat
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    kAccent.opacity(0.25)
                    Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct Empty: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("All clear").font(.headline).foregroundStyle(.white)
            Text("Nothing about to charge you.").font(.caption2).foregroundStyle(kMuted)
        }
    }
}

struct TrialWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    var body: some View {
        let trials = entry.trials.filter { $0.end > entry.date }
        VStack(alignment: .leading, spacing: 6) {
            Header(count: trials.count)
            Spacer(minLength: 0)
            if trials.isEmpty {
                Empty()
            } else if family == .systemSmall, let t = trials.first {
                RingLogo(t: t, image: entry.logos[t.name], now: entry.date, size: 38)
                Text(t.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                Countdown(end: t.end, now: entry.date).font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1)
                Text(t.label).font(.caption2).foregroundStyle(kMuted).lineLimit(1)
            } else {
                ForEach(trials.prefix(family == .systemLarge ? 5 : 3)) { t in
                    HStack(spacing: 8) {
                        RingLogo(t: t, image: entry.logos[t.name], now: entry.date, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                            Text(t.label).font(.caption2).foregroundStyle(kMuted).lineLimit(1)
                        }
                        Spacer()
                        Countdown(end: t.end, now: entry.date).font(.subheadline.bold()).multilineTextAlignment(.trailing)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            ZStack {
                kBg
                RadialGradient(colors: [kGlow.opacity(0.45), .clear], center: .topTrailing, startRadius: 0, endRadius: 180)
            }
        }
    }
}

@main
struct TrialWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TrialWidget", provider: Provider()) { TrialWidgetView(entry: $0) }
            .configurationDisplayName("Upcoming Charges")
            .description("Countdown to your next trial and subscription charges.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
