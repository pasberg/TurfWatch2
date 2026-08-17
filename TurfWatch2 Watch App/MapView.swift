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
    @State private var mapWidth: CGFloat = 0

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
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { mapWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newValue in mapWidth = newValue }
                }
            )

            // Scale indicator (bottom-leading)
            if let scale = scaleBar(mapWidth: mapWidth) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scale.label)
                        .font(.system(size: 9, weight: .semibold))
                    Rectangle()
                        .frame(width: scale.width, height: 3)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 8)
                .padding(.bottom, 10)
                .allowsHitTesting(false)
            }

            // Stats header (top) — points/hour, round points, zones held
            if let user = appState.currentUser {
                statsHeader(user)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }

            // Zoom controls (centre-right, clear of the header)
            VStack(spacing: 6) {
                mapButton(systemName: "plus") { zoom(by: 0.5) }
                mapButton(systemName: "minus") { zoom(by: 2.0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 6)

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
        .sheet(item: selectedZoneBinding) { zone in
            NavigationStack {
                ZoneDetailView(zone: zone)
            }
        }
        .task {
            appState.requestLocation()
            if appState.currentUser == nil {
                await appState.refreshUser()
            }
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

    /// Top bar mirroring the phone app: points/hour, points this round, zones held.
    private func statsHeader(_ user: TurfUser) -> some View {
        HStack(spacing: 0) {
            headerStat(value: "+\(user.pointsPerHour ?? 0)", caption: "p/h", color: .green)
            headerDivider
            headerStat(value: (user.points ?? 0).formatted(), caption: "poäng", color: .yellow)
            headerDivider
            headerStat(value: "\(user.zones?.count ?? 0)", caption: "zoner", color: .blue)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func headerStat(value: String, caption: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caption)
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 32)
    }

    private var headerDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 16)
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

    /// Computes a map scale bar: a "nice" rounded distance and the bar width in
    /// points that represents it at the current zoom.
    private func scaleBar(mapWidth: CGFloat) -> (label: String, width: CGFloat)? {
        guard mapWidth > 0 else { return nil }
        let centerLat = region.center.latitude * .pi / 180
        let metersPerDegLon = 111_320.0 * cos(centerLat)
        let regionWidthMeters = region.span.longitudeDelta * metersPerDegLon
        guard regionWidthMeters.isFinite, regionWidthMeters > 0 else { return nil }

        let metersPerPoint = regionWidthMeters / Double(mapWidth)
        let niceMeters = niceRound(metersPerPoint * 64) // aim for a ~64pt bar
        let barPoints = CGFloat(niceMeters / metersPerPoint)
        guard barPoints.isFinite, barPoints > 0 else { return nil }
        return (formatDistanceLabel(niceMeters), barPoints)
    }

    /// Rounds a distance to the nearest 1/2/5 × 10ⁿ for a tidy scale bar.
    private func niceRound(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        let exponent = floor(log10(value))
        let base = pow(10.0, exponent)
        let fraction = value / base
        let nice: Double = fraction < 1.5 ? 1 : (fraction < 3.5 ? 2 : (fraction < 7.5 ? 5 : 10))
        return nice * base
    }

    private func formatDistanceLabel(_ meters: Double) -> String {
        if meters >= 1000 {
            let km = meters / 1000
            return km == floor(km) ? "\(Int(km)) km" : String(format: "%.1f km", km)
        }
        return "\(Int(meters)) m"
    }

    /// Bridges the selected zone id to an optional zone for the detail sheet.
    private var selectedZoneBinding: Binding<TurfZone?> {
        Binding(
            get: { appState.nearbyZones.first { $0.id == selectedZoneID } },
            set: { newValue in selectedZoneID = newValue?.id }
        )
    }
}
