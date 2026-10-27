//  Cooldown home-screen + lock-screen widget (iOS 17+).
//  Reads the same JSON the Flutter app writes into the shared App Group.
//  The schedule + formatting logic mirrors lib/models/cooldown.dart and
//  lib/utils/format.dart — keep them in sync.

import AppIntents
import SwiftUI
import WidgetKit

let appGroupId = "group.com.berkan.cooldown"

// MARK: - Data

struct CooldownData: Codable, Identifiable {
    let id: String
    let name: String
    let emoji: String
    let color: Int64
    let targetMs: Double
    let startMs: Double
    let repeatValue: Int
    let repeatUnit: String
    let waitForDone: Bool
    let display: String?

    var repeats: Bool { repeatValue > 0 }
    private var autoRepeats: Bool { repeats && !waitForDone }
    private var anchor: Date { Date(timeIntervalSince1970: targetMs / 1000) }
    private var startDate: Date { Date(timeIntervalSince1970: startMs / 1000) }

    var swiftColor: Color {
        Color(
            red: Double((color >> 16) & 0xFF) / 255,
            green: Double((color >> 8) & 0xFF) / 255,
            blue: Double(color & 0xFF) / 255
        )
    }

    private func occurrence(_ k: Int) -> Date {
        let n = repeatValue * k
        let cal = Calendar.current
        switch repeatUnit {
        case "hours": return anchor.addingTimeInterval(Double(n) * 3600)
        case "weeks": return cal.date(byAdding: .day, value: 7 * n, to: anchor) ?? anchor
        case "months": return cal.date(byAdding: .month, value: n, to: anchor) ?? anchor
        case "years": return cal.date(byAdding: .year, value: n, to: anchor) ?? anchor
        default: return cal.date(byAdding: .day, value: n, to: anchor) ?? anchor
        }
    }

    private var approxInterval: Double {
        let h = 3600.0
        let unit: Double
        switch repeatUnit {
        case "hours": unit = h
        case "weeks": unit = 7 * 24 * h
        case "months": unit = 31 * 24 * h
        case "years": unit = 366 * 24 * h
        default: unit = 24 * h
        }
        return Double(repeatValue) * unit
    }

    /// (start, end) of the cycle that is current at `now`.
    func currentCycle(_ now: Date) -> (start: Date, end: Date) {
        if !autoRepeats || anchor > now { return (startDate, anchor) }
        var k = max(0, Int(now.timeIntervalSince(anchor) / approxInterval) - 2)
        var end = occurrence(k)
        while end <= now {
            k += 1
            end = occurrence(k)
        }
        return (k == 0 ? startDate : occurrence(k - 1), end)
    }
}

enum CooldownStore {
    static func defaults() -> UserDefaults? { UserDefaults(suiteName: appGroupId) }

    static func all() -> [CooldownData] {
        guard let raw = defaults()?.string(forKey: "cooldowns"),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([CooldownData].self, from: data)
        else { return [] }
        return list
    }

    static var defaultFormat: String { defaults()?.string(forKey: "default_display") ?? "days" }
}

// MARK: - Formatting

enum CooldownFormat {
    private static func hm(_ s: Int) -> String {
        let h = s / 3600, m = (s / 60) % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }

    private static func dhm(_ s: Int) -> String {
        let d = s / 86400, h = (s / 3600) % 24, m = (s / 60) % 60
        return d > 0 ? "\(d)d \(h)h \(m)m" : hm(s)
    }

    static func remaining(now: Date, end: Date, format: String) -> (value: String, label: String) {
        let left = Int(end.timeIntervalSince(now))
        if left <= 0 { return ("0", "ready") }
        let cal = Calendar.current
        let calDays = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: end)).day ?? 0

        func days() -> (String, String) {
            calDays >= 1 ? ("\(calDays)", calDays == 1 ? "day" : "days") : (hm(left), "left today")
        }

        switch format {
        case "weeks":
            if calDays >= 7 {
                let w = calDays / 7, d = calDays % 7
                return (d == 0 ? "\(w)w" : "\(w)w \(d)d", "left")
            }
            return days()
        case "hours":
            let h = left / 3600
            if h >= 1 { return ("\(h)", h == 1 ? "hour" : "hours") }
            let m = left / 60
            return (m > 0 ? "\(m)" : "<1", "min")
        case "detailed":
            return (dhm(left), "left")
        case "auto":
            return calDays >= 2 ? days() : (dhm(left), "left")
        default:
            return days()
        }
    }

    static func isFineGrained(now: Date, end: Date, format: String) -> Bool {
        let left = end.timeIntervalSince(now)
        switch format {
        case "hours", "detailed": return true
        case "auto": return left < 3 * 86400
        default: return left < 2 * 86400
        }
    }
}

// MARK: - Configuration ("Edit Widget" → pick a cooldown)

struct CooldownEntity: AppEntity {
    let id: String
    let title: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Cooldown"
    static let defaultQuery = CooldownQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct CooldownQuery: EntityQuery {
    private func load() -> [CooldownEntity] {
        CooldownStore.all().map { CooldownEntity(id: $0.id, title: "\($0.emoji) \($0.name)") }
    }

    func entities(for identifiers: [String]) async throws -> [CooldownEntity] {
        load().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CooldownEntity] { load() }

    func defaultResult() async -> CooldownEntity? { load().first }
}

struct SelectCooldownIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose cooldown"
    static let description = IntentDescription("Pick which cooldown this widget shows.")

    @Parameter(title: "Cooldown")
    var cooldown: CooldownEntity?
}

// MARK: - Timeline

struct CooldownEntry: TimelineEntry {
    let date: Date
    let cooldown: CooldownData?
    let format: String
}

struct Provider: AppIntentTimelineProvider {
    private func resolve(_ config: SelectCooldownIntent) -> (CooldownData?, String) {
        let all = CooldownStore.all()
        let c: CooldownData?
        if let picked = config.cooldown {
            c = all.first(where: { $0.id == picked.id })
        } else {
            c = all.first // not configured yet: show the first cooldown
        }
        var fmt = CooldownStore.defaultFormat
        if let d = c?.display, d != "default" { fmt = d }
        return (c, fmt)
    }

    func placeholder(in context: Context) -> CooldownEntry {
        let sample = CooldownData(
            id: "sample", name: "Water plants", emoji: "🌱", color: 0xFF3A9D5D,
            targetMs: Date().addingTimeInterval(3 * 86400).timeIntervalSince1970 * 1000,
            startMs: Date().timeIntervalSince1970 * 1000,
            repeatValue: 3, repeatUnit: "days", waitForDone: true, display: "days")
        return CooldownEntry(date: Date(), cooldown: sample, format: "days")
    }

    func snapshot(for configuration: SelectCooldownIntent, in context: Context) async -> CooldownEntry {
        let (c, fmt) = resolve(configuration)
        return c == nil && context.isPreview ? placeholder(in: context) : CooldownEntry(date: Date(), cooldown: c, format: fmt)
    }

    func timeline(for configuration: SelectCooldownIntent, in context: Context) async -> Timeline<CooldownEntry> {
        let (c, fmt) = resolve(configuration)
        let now = Date()
        guard let c else {
            return Timeline(entries: [CooldownEntry(date: now, cooldown: nil, format: fmt)], policy: .never)
        }

        // Pre-compute what the widget shows over the next hours; the app also
        // reloads the timeline whenever anything changes.
        var dates: [Date] = [now]
        var t = now
        let horizon = now.addingTimeInterval(24 * 3600)
        while t < horizon && dates.count < 200 {
            let end = c.currentCycle(t).end
            if end <= t { break } // finished and waiting: nothing changes anymore
            let step: Double = CooldownFormat.isFineGrained(now: t, end: end, format: fmt) ? 60 : 900
            var next = t.addingTimeInterval(step)
            if end > t && end < next { next = end.addingTimeInterval(1) }
            dates.append(next)
            t = next
        }
        let entries = dates.map { CooldownEntry(date: $0, cooldown: c, format: fmt) }
        let reloadAt = max(dates.last ?? now, now.addingTimeInterval(1800))
        return Timeline(entries: entries, policy: .after(reloadAt))
    }
}

// MARK: - Views

struct CooldownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CooldownEntry

    var body: some View {
        if let c = entry.cooldown {
            content(c)
        } else {
            VStack(spacing: 4) {
                Text("⏳").font(.title)
                Text("Long-press → Edit Widget to choose a cooldown")
                    .font(.caption).multilineTextAlignment(.center)
            }
            .containerBackground(for: .widget) { Color.gray.opacity(0.25) }
        }
    }

    @ViewBuilder
    private func content(_ c: CooldownData) -> some View {
        let cycle = c.currentCycle(entry.date)
        let finished = cycle.end <= entry.date
        let r = CooldownFormat.remaining(now: entry.date, end: cycle.end, format: entry.format)
        let value = finished ? (c.repeats ? "Ready" : "Done") : r.value
        let label = finished ? (c.repeats ? "tap to mark done" : "🎉") : r.label
        let total = max(1, cycle.end.timeIntervalSince(cycle.start))
        let progress = min(1, max(0, entry.date.timeIntervalSince(cycle.start) / total))

        switch family {
        case .accessoryInline:
            Text("\(c.emoji) \(value) \(label)")
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            Gauge(value: progress) {
                Text(c.emoji)
            } currentValueLabel: {
                Text(value).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(c.emoji) \(c.name)").font(.headline).lineLimit(1)
                Text("\(value) \(label)").font(.body).lineLimit(1)
                ProgressView(value: progress)
            }
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(c.emoji) \(c.name)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: family == .systemSmall ? 34 : 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                Text(label).font(.caption).opacity(0.9)
                ProgressView(value: progress)
                    .tint(.white)
                    .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { c.swiftColor }
        }
    }
}

// MARK: - Widget

struct CooldownWidget: Widget {
    // Must match kIOSWidgetKind in lib/services/store.dart
    let kind = "CooldownWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectCooldownIntent.self, provider: Provider()) { entry in
            CooldownWidgetView(entry: entry)
        }
        .configurationDisplayName("Cooldown")
        .description("Shows the time left on one of your cooldowns.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

@main
struct CooldownWidgetBundle: WidgetBundle {
    var body: some Widget {
        CooldownWidget()
    }
}
