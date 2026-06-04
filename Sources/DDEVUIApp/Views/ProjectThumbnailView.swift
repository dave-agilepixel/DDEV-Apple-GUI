import SwiftUI

/// Renders a project's cached homepage thumbnail as a rounded rect, or falls back to the project
/// type's SF Symbol when there is no thumbnail. Used both in the list row (small) and the inspector
/// header (large), so the fallback looks identical everywhere.
struct ProjectThumbnailView: View {
    let thumbnail: Data?
    let fallbackSymbol: String
    var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            if let thumbnail, let image = NSImage(data: thumbnail) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary.opacity(0.4))
                Image(systemName: fallbackSymbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
