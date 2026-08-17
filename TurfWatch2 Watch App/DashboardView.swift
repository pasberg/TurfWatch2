import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            if appState.isLoadingUser && appState.currentUser == nil {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Laddar...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
            } else if let user = appState.currentUser {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 36, height: 36)
                            Text(String(user.name.prefix(2)).uppercased())
                                .font(.caption)
                                .bold()
                                .foregroundColor(.green)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(user.name)
                                .font(.subheadline)
                                .bold()
                                .lineLimit(1)
                            if let region = user.region {
                                Text(region.name)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.bottom, 8)

                    Divider()
                        .padding(.bottom, 6)

                    // Stats
                    StatRow(label: "Poäng", value: (user.points ?? 0).formatted(), color: .yellow)
                    StatRow(label: "Rank", value: user.displayRank.map { "#\($0)" } ?? "–", color: .orange)
                    StatRow(label: "Poäng/h", value: "+\(user.pointsPerHour ?? 0)", color: .green)
                    StatRow(label: "Zoner", value: "\(user.zones?.count ?? 0)", color: .blue)
                    StatRow(label: "Taggar", value: "\(user.taken ?? 0)", color: .purple)

                    if let error = appState.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(.top, 6)
                    }

                    // Logout
                    Button(role: .destructive) {
                        appState.logout()
                    } label: {
                        Label("Logga ut", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.caption2)
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal)
            } else if let error = appState.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Försök igen") {
                        Task { await appState.refreshUser() }
                    }
                    .font(.caption2)
                }
                .padding()
            }
        }
        .navigationTitle("Min profil")
        .task {
            if appState.currentUser == nil {
                await appState.refreshUser()
            }
        }
        .refreshable {
            await appState.refreshUser()
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .bold()
                .foregroundColor(color)
        }
        .padding(.vertical, 3)
    }
}
