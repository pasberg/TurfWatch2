import SwiftUI
import MapKit

struct ZoneDetailView: View {
    let zone: TurfZone
    @EnvironmentObject var appState: AppState

    private var initialRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: zone.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0016, longitudeDelta: 0.0016)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                // Status badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.zoneColor(zone))
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                        .frame(width: 9, height: 9)
                    Text(appState.zoneStatusText(zone))
                        .font(.caption)
                        .foregroundColor(appState.zoneColor(zone) == .black ? .primary : appState.zoneColor(zone))
                        .bold()
                }
                .padding(.bottom, 2)

                // Live block countdown — ticks down until the zone can be taken.
                if let end = appState.blockEndDate(for: zone) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, end.timeIntervalSince(context.date))
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                            Text(appState.isMyZone(zone)
                                 ? "Tagen – fri om \(MapView.mmss(remaining))"
                                 : "Blockerad \(MapView.mmss(remaining))")
                        }
                        .font(.caption2).bold()
                        .foregroundColor(appState.isMyZone(zone) ? .green : .orange)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 2)
                }

                Divider()

                if let type = zone.type {
                    StatRow(label: "Typ", value: type.name, color: .cyan)
                }
                if let area = zone.region?.area {
                    StatRow(label: "Område", value: area.name)
                } else if let region = zone.region {
                    StatRow(label: "Region", value: region.name)
                }
                StatRow(label: "Poäng/h", value: "\(zone.pointsPerHour ?? 0) p", color: .green)
                StatRow(label: "Takeover", value: "\(zone.takeoverPoints ?? 0) p", color: .yellow)
                StatRow(label: "Taggar", value: "\(zone.totalTakeovers ?? 0)")

                if let dist = appState.distanceTo(zone) {
                    StatRow(label: "Avstånd", value: appState.formatDistance(dist), color: .blue)
                }

                // Mini map showing the zone as an area
                Map(initialPosition: .region(initialRegion), interactionModes: []) {
                    let color = appState.zoneColor(zone)
                    if let boundary = zone.areaCoordinates {
                        MapPolygon(coordinates: boundary)
                            .foregroundStyle(color.opacity(0.3))
                            .stroke(color, lineWidth: 1.5)
                    } else {
                        MapCircle(center: zone.coordinate, radius: zone.areaRadius)
                            .foregroundStyle(color.opacity(0.3))
                            .stroke(color, lineWidth: 1.5)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 90)
                .cornerRadius(10)
                .padding(.top, 4)

                if let ago = appState.lastTakenText(zone) {
                    Text("Senast tagen: \(ago)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }

                // Test: simulate taking this zone so you can see the countdown run.
                Button {
                    appState.simulateTakeover(zone)
                } label: {
                    Label("Simulera tagning (test)", systemImage: "flag.fill")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .padding(.top, 4)
            }
            .padding(.horizontal)
        }
        .navigationTitle(zone.name)
    }
}
