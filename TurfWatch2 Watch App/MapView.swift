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
    @State private var region = MapView.fallbackRegion
    @State private var selectedZoneID: Int?

    var body: some View {
        ZStack {
            Map(position: $camera, selection: $selectedZoneID) {
                UserAnnotation()

                ForEach(appState.nearbyZones) { zone in
                    let color = appState.zoneColor(zone)

                    // The zone AREA — irregular polygon when boundary data exists,
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
            .onMapCameraChange(frequency: .continuous) { context in
                region = context.region
            }

            // Zoom controls (top-trailing)
            VStack(spacing: 6) {
                mapButton(systemName: "plus") { zoom(by: 0.5) }
                mapButton(systemName: "minus") { zoom(by: 2.0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(6)

            // Recenter (bottom-trailing)
            mapButton(systemName: "location.fill") {
                withAnimation { camera = .userLocation(fallback: .region(Self.fallbackRegion)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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

    private func mapButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// Zooms around the current map center. factor < 1 zooms in, > 1 zooms out.
    private func zoom(by factor: Double) {
        let latD = min(max(region.span.latitudeDelta * factor, 0.0015), 80)
        let lonD = min(max(region.span.longitudeDelta * factor, 0.0015), 80)
        let zoomed = MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(latitudeDelta: latD, longitudeDelta: lonD)
        )
        region = zoomed
        withAnimation(.easeInOut(duration: 0.25)) {
            camera = .region(zoomed)
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
