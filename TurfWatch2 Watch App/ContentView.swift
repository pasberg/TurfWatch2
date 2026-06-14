import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.isLoggedIn {
            TabView {
                NavigationStack {
                    DashboardView()
                }
                NavigationStack {
                    NearbyZonesView()
                }
            }
            .tabViewStyle(.page)
        } else {
            LoginView()
        }
    }
}
