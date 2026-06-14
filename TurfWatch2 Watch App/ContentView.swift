import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.isLoggedIn {
            TabView {
                NavigationStack {
                    MapView()
                }
                NavigationStack {
                    NearbyZonesView()
                }
                NavigationStack {
                    DashboardView()
                }
            }
            .tabViewStyle(.page)
        } else {
            LoginView()
        }
    }
}
