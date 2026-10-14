import SwiftUI

/// Loads a small image file off the main thread.
struct ThumbnailView: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        // The image is an overlay so it never changes the size the parent proposed.
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    Image(systemName: "photo")
                        .font(.title3.weight(.light))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipped()
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: url.path)
            }.value
        }
    }
}
