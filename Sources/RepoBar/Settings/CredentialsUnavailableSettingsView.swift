import SwiftUI

struct CredentialsUnavailableSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AccountAttention.credentialsUnavailable.title ?? "")
                .font(.headline)
            Text(AccountAttention.credentialsUnavailable.subtitle ?? "")
                .foregroundStyle(.secondary)
            Button(AppLocalizer().string("Relaunch RepoBar")) {
                AppRelauncher.relaunch()
            }
        }
    }
}
