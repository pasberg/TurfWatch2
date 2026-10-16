import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState

    @State private var username = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 32))
                    .foregroundColor(.green)
                    .padding(.top, 4)

                Text("TurfWatch")
                    .font(.headline)

                Text("Ange ditt Turf-användarnamn")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Användarnamn", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if let msg = error {
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await doLogin() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Fortsätt")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding(.horizontal)
        }
    }

    private func doLogin() async {
        isLoading = true
        error = nil
        do {
            try await appState.login(username: username)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
