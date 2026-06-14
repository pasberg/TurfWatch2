import SwiftUI
import MapKit

struct ZoneDetailView: View {
    let zone: TurfZone
    @EnvironmentObject var appState: AppState

    @State private var region: MKCoordinateRegion

    init(zone: TurfZone) {
        self.zone = zone
        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: zone.latitude, longitude: zone.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
        ))
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

                // Mini map
                Map(coordinateRegion: $region, annotationItems: [ZoneAnnotation(zone: zone)]) { item in
                    MapMarker(coordinate: item.coordinate, tint: appState.zoneColor(zone))
                }
                .frame(height: 90)
                .cornerRadius(10)
                .disabled(true)
                .padding(.top, 4)
            }
            .padding(.horizontal)
        }
        .navigationTitle(zone.name)
    }
}

private struct ZoneAnnotation: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D

    init(zone: TurfZone) {
        id = zone.id
        coordinate = CLLocationCoordinate2D(latitude: zone.latitude, longitude: zone.longitude)
    }
}
