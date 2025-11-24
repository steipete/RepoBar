import SwiftUI

struct ContributionHeaderView: View {
    let username: String?

    var body: some View {
        if let username {
            AsyncImage(url: URL(string: "https://ghchart.rshah.org/\(username)")) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 500)
                        .accessibilityLabel("Contribution graph for \(username)")
                case .failure:
                    self.placeholder
                @unknown default:
                    self.placeholder
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .frame(height: 80)
            .accessibilityLabel("Contribution graph unavailable")
    }
}
