import WidgetKit
import SwiftUI

// MARK: - Entry

struct TurfEntry: TimelineEntry {
    let date: Date
    let pph: Int
    let points: Int
    let zones: Int
    let nearestZone: String
}

// MARK: - Provider (reads the stats the app writes to the shared App Group)

struct TurfProvider: TimelineProvider {
    private let appGroup = "group.com.pasberg.TurfWatch2"

    private func load() -> TurfEntry {
        let d = UserDefaults(suiteName: appGroup)
        return TurfEntry(
            date: Date(),
            pph: d?.integer(forKey: "pph") ?? 0,
            points: d?.integer(forKey: "points") ?? 0,
            zones: d?.integer(forKey: "zones") ?? 0,
            nearestZone: d?.string(forKey: "nearestZone") ?? "—"
        )
    }

    func placeholder(in context: Context) -> TurfEntry {
        TurfEntry(date: Date(), pph: 24, points: 21692, zones: 6, nearestZone: "KungFrilles")
    }

    func getSnapshot(in context: Context, completion: @escaping (TurfEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TurfEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [load()], policy: .after(next)))
    }
}

// MARK: - View

struct TurfComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: TurfEntry

    var body: some View {
        content
            .containerBackground(.clear, for: .widget)
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
                Text("Turf").font(.headline)
                Text("+\(entry.pph) p/h · \(entry.points) p")
                Text("\(entry.zones) zoner · \(entry.nearestZone)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .description("Dina poäng/h, poäng och antal zoner.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
        ])
    }
}
