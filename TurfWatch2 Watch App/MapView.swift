import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @EnvironmentObject var appState: AppState

    private static let fallbackRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 59.3293, longitude: 18.0686), // Stockholm fallback
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(fallbackRegion))
    @State private var selectedZoneID: Int?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $camera, selection: $selectedZoneID) {
                UserAnnotation()

                ForEach(appState.nearbyZones) { zone in
                    let color = appState.zoneColor(zone)

                    // The zone AREA — an irregular polygon if boundary data exists,
                    // otherwise a circle of the zone's real size around its center.
                    if let boundary = zone.areaCoordinates {
                        MapPolygon(coordinates: boundary)
                            .foregroundStyle(color.opacity(0.28))
                            .stroke(color, lineWidth: 1.4)
                    } else {
                        MapCircle(center: zone.coordinate, radius: zone.areaRadius)
                            .foregroundStyle(color.opacity(0.28))
                            .stroke(color, lineWidth: 1.4)
                    }

                    // A small tappable marker at the center for selection.
                    Annotation(zone.name, coordinate: zone.coordinate) {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(.white, lineWidth: 1.2))
                    }
                    .tag(zone.id)
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))

            // Recenter button
            Button {
                withAnimation {
                    camera = .userLocation(fallback: .region(Self.fallbackRegion))
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 13))
                    .padding(7)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)

            if appState.isLoadingZones {
                ProgressView()
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            }
        }
        .navigationTitle("Karta")
        .sheet(item: selectedZoneBinding) { zone in
            NavigationStack {
                ZoneDetailView(zone: zone)
            }
        }
        .task {
            appState.requestLocation()
            if appState.location != nil, appState.nearbyZones.isEmpty {
                await appState.refreshNearbyZones()
            }
        }
        .onChange(of: appState.location) { loc in
            if loc != nil, appState.nearbyZones.isEmpty {
                Task { await appState.refreshNearbyZones() }
            }
        }
    }

    /// Bridges the selected zone id to an optional zone for the detail sheet.
    private var selectedZoneBinding: Binding<TurfZone?> {
        Binding(
            get: { appState.nearbyZones.first { $0.id == selectedZoneID } },
            set: { newValue in selectedZoneID = newValue?.id }
        )
    }
}
