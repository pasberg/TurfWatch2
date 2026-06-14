import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @EnvironmentObject var appState: AppState

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 59.3293, longitude: 18.0686), // Stockholm fallback
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var hasCenteredOnUser = false
    @State private var selectedZone: TurfZone?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(
                coordinateRegion: $region,
                showsUserLocation: true,
                annotationItems: appState.nearbyZones
            ) { zone in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: zone.latitude, longitude: zone.longitude)) {
                    ZoneMarker(zone: zone, isSelected: selectedZone?.id == zone.id)
                        .onTapGesture { selectedZone = zone }
                }
            }
            .ignoresSafeArea()

            // Recenter button
            Button {
                centerOnUser(animated: true)
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 13))
                    .padding(7)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)

            // Loading indicator
            if appState.isLoadingZones {
                ProgressView()
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            }
        }
        .navigationTitle("Karta")
        .sheet(item: $selectedZone) { zone in
            NavigationStack {
                ZoneDetailView(zone: zone)
            }
        }
        .task {
            appState.requestLocation()
            if appState.location != nil {
                centerOnUser(animated: false)
                if appState.nearbyZones.isEmpty {
                    await appState.refreshNearbyZones()
                }
            }
        }
        .onChange(of: appState.location) { loc in
            guard loc != nil else { return }
            if !hasCenteredOnUser {
                centerOnUser(animated: false)
            }
            if appState.nearbyZones.isEmpty {
                Task { await appState.refreshNearbyZones() }
            }
        }
    }

    private func centerOnUser(animated: Bool) {
        guard let loc = appState.location else { return }
        hasCenteredOnUser = true
        let newRegion = MKCoordinateRegion(
            center: loc.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        )
        if animated {
            withAnimation { region = newRegion }
        } else {
            region = newRegion
        }
    }
}

struct ZoneMarker: View {
    let zone: TurfZone
    let isSelected: Bool
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: isSelected ? 16 : 11, height: isSelected ? 16 : 11)
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: isSelected ? 16 : 11, height: isSelected ? 16 : 11)
            }
            if isSelected {
                Text(zone.name)
                    .font(.system(size: 9))
                    .bold()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.ultraThinMaterial, in: Capsule())
                    .lineLimit(1)
            }
        }
    }

    private var color: Color {
        guard zone.currentOwner != nil else { return .gray }
        return appState.isMyZone(zone) ? .green : .blue
    }
}
