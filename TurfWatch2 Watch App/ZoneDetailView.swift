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

                Divider()

                if let region = zone.region {
                    StatRow(label: "Region", value: region.name)
                }
                StatRow(label: "Poäng/h", value: "\(zone.pointsPerHour) p", color: .green)
                StatRow(label: "Takeover", value: "\(zone.takeoverPoints) p", color: .yellow)
                StatRow(label: "Taggar", value: "\(zone.totalTakeovers)")

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
            }
            .padding(.horizontal)
        }
        .navigationTitle(zone.name)
    }
}
