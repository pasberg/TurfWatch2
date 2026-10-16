import WidgetKit
import SwiftUI

// MARK: - Ändra till ditt Turf-användarnamn
private let kUsername = "Ventruce"

// MARK: - Entry

struct TurfEntry: TimelineEntry {
    let date: Date
    let username: String
    let pph: Int
    let points: Int
    let zones: Int
}

// MARK: - Self-contained Turf API fetch (no App Group / shared storage needed)

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

// MARK: - Provider (classic, stable TimelineProvider)

struct TurfProvider: TimelineProvider {
    func placeholder(in context: Context) -> TurfEntry {
        TurfEntry(date: Date(), username: kUsername, pph: 24, points: 21692, zones: 6)
    }

    func getSnapshot(in context: Context, completion: @escaping (TurfEntry) -> Void) {
        Task { completion(await loadEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TurfEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let next = Date().addingTimeInterval(20 * 60) // refresh ~every 20 min
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func loadEntry() async -> TurfEntry {
        let u = await fetchTurfUser(kUsername)
        return TurfEntry(
            date: Date(),
            username: u?.name ?? kUsername,
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
        StaticConfiguration(kind: "TurfComplication", provider: TurfProvider()) { entry in
            TurfComplicationView(entry: entry)
        }
        .configurationDisplayName("Turf")
        .description("Din Turf-statistik.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
        ])
    }
}
