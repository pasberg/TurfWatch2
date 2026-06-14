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
                        .fill(zoneColor)
                        .frame(width: 9, height: 9)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(zoneColor)
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
                    MapMarker(coordinate: item.coordinate, tint: zoneColor)
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

    private var statusText: String {
        guard let owner = zone.currentOwner else { return "Neutral" }
        return appState.isMyZone(zone) ? "Din zon" : owner.name
    }

    private var zoneColor: Color {
        guard let _ = zone.currentOwner else { return .gray }
        return appState.isMyZone(zone) ? .green : .blue
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
