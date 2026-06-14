import SwiftUI

struct NearbyZonesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.locationDenied {
                VStack(spacing: 8) {
                    Image(systemName: "location.slash")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Platsåtkomst nekad")
                        .font(.caption)
                    Text("Aktivera i Inställningar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if appState.isLoadingZones && appState.nearbyZones.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Söker zoner...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if appState.nearbyZones.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Inga zoner hittades")
                        .font(.caption)
                    if let error = appState.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    Button("Uppdatera") {
                        Task { await appState.refreshNearbyZones() }
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .foregroundColor(.green)
                }
                .padding()
            } else {
                List(appState.nearbyZones) { zone in
                    NavigationLink(destination: ZoneDetailView(zone: zone)) {
                        ZoneRow(zone: zone)
                    }
                }
                .refreshable {
                    await appState.refreshNearbyZones()
                }
            }
        }
        .navigationTitle("Zoner")
        .task {
            if appState.nearbyZones.isEmpty {
                appState.requestLocation()
                if appState.location != nil {
                    await appState.refreshNearbyZones()
                }
            }
        }
        .onChange(of: appState.location) { loc in
            if loc != nil && appState.nearbyZones.isEmpty {
                Task { await appState.refreshNearbyZones() }
            }
        }
    }
}

struct ZoneRow: View {
    let zone: TurfZone
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(appState.zoneColor(zone))
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                    .frame(width: 7, height: 7)
                Text(zone.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            HStack {
                Text(appState.zoneStatusText(zone))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                if let dist = appState.distanceTo(zone) {
                    Text(appState.formatDistance(dist))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
