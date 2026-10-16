import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration (the user types their Turf username in the complication
// settings; no App Group / shared storage needed).

struct TurfConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Turf" }
    static var description: IntentDescription { "Visa statistik för ett Turf-användarnamn." }

    @Parameter(title: "Användarnamn", default: "Ventruce")
    var username: String
}

// MARK: - Entry

struct TurfEntry: TimelineEntry {
    let date: Date
    let username: String
    let pph: Int
    let points: Int
    let zones: Int
}

// MARK: - Self-contained Turf API fetch

private struct TurfUserLite: Decodable {
    let name: String
    let points: Int?
    let pointsPerHour: Int?
    let zones: [Int]?
}

private func fetchTurfUser(_ name: String) async -> TurfUserLite? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let url = URL(string: "https://api.turfgame.com/v4/users") else { return nil }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.httpBody = try? JSONSerialization.data(withJSONObject: [["name": trimmed]])
    guard let (data, resp) = try? await URLSession.shared.data(for: req),
          (resp as? HTTPURLResponse)?.statusCode == 200,
          let users = try? JSONDecoder().decode([TurfUserLite].self, from: data) else { return nil }
    return users.first
}

// MARK: - Provider

struct TurfProvider: AppIntentTimelineProvider {
    typealias Entry = TurfEntry
    typealias Intent = TurfConfigIntent

    func placeholder(in context: TimelineProviderContext) -> TurfEntry {
        TurfEntry(date: Date(), username: "Ventruce", pph: 24, points: 21692, zones: 6)
    }

    func snapshot(for configuration: TurfConfigIntent, in context: TimelineProviderContext) async -> TurfEntry {
        await entry(for: configuration.username)
    }

    func timeline(for configuration: TurfConfigIntent, in context: TimelineProviderContext) async -> Timeline<TurfEntry> {
        let e = await entry(for: configuration.username)
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(1200)
        return Timeline(entries: [e], policy: .after(next))
    }

    private func entry(for username: String) async -> TurfEntry {
        let u = await fetchTurfUser(username)
        return TurfEntry(
            date: Date(),
            username: u?.name ?? username,
            pph: u?.pointsPerHour ?? 0,
            points: u?.points ?? 0,
            zones: u?.zones?.count ?? 0
        )
    }
}

// MARK: - View

struct TurfComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: TurfEntry

    var body: some View {
        content.containerBackground(.clear, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text("\(entry.pph) p/h · \(entry.zones) zoner")

        case .accessoryCircular:
            Gauge(value: Double(min(entry.pph, 60)), in: 0...60) {
                Text("p/h")
            } currentValueLabel: {
                Text("\(entry.pph)")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.green)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.username).font(.headline)
                Text("+\(entry.pph) p/h · \(entry.points) p")
                Text("\(entry.zones) zoner")
                    .foregroundStyle(.secondary)
            }

        case .accessoryCorner:
            Text("\(entry.pph)")
                .widgetLabel("p/h")

        @unknown default:
            Text("\(entry.pph) p/h")
        }
    }
}

// MARK: - Widget

@main
struct TurfComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TurfComplication", intent: TurfConfigIntent.self, provider: TurfProvider()) { entry in
            TurfComplicationView(entry: entry)
        }
        .configurationDisplayName("Turf")
        .description("Statistik för ett Turf-användarnamn.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
        ])
    }
}
