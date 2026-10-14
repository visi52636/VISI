import SwiftUI

/// Full-screen 360° viewer with navigation between the panoramas of a project.
@MainActor
struct PanoramaViewerView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    let projectID: Project.ID
    @State private var currentID: Panorama.ID
    @State private var image: UIImage?
    @State private var loadFailed = false
    @State private var motionEnabled = false
    @State private var resetToken = 0
    @State private var controlsVisible = true
    @State private var sharePayload: SharePayload?
    @State private var layoutImage: UIImage?
    @State private var showMap = true

    /// Maximum texture width; 8192 px keeps detail while staying within GPU and memory limits.
    private static let maxTextureSize = 8192

    init(projectID: Project.ID, initialPanoramaID: Panorama.ID) {
        self.projectID = projectID
        _currentID = State(initialValue: initialPanoramaID)
    }

    private var panoramas: [Panorama] { store.project(id: projectID)?.panoramas ?? [] }
    private var currentIndex: Int? { panoramas.firstIndex { $0.id == currentID } }
    private var current: Panorama? { currentIndex.map { panoramas[$0] } }
    private var layoutURL: URL? { store.project(id: projectID).flatMap { store.layoutImageURL(for: $0) } }
    private var hasPlacedPanoramas: Bool { panoramas.contains { $0.layoutPosition != nil } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                PanoramaSceneView(image: image, motionEnabled: $motionEnabled, resetToken: resetToken)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { controlsVisible.toggle() } }
            } else if loadFailed {
                Label("Unable to load this panorama.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }

            if controlsVisible {
                controls
                    .transition(.opacity)
            }
        }
        .statusBarHidden(!controlsVisible)
        .task(id: currentID) { await loadImage() }
        .task(id: layoutURL) {
            guard let url = layoutURL else { layoutImage = nil; return }
            layoutImage = await Task.detached(priority: .utility) {
                ImageProcessing.downsampledImage(at: url, maxPixelSize: 2048)
            }.value
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
    }

    private var controls: some View {
        VStack {
            HStack(alignment: .top) {
                CircleButton(systemImage: "xmark") { dismiss() }
                Spacer()
                VStack(spacing: 2) {
                    Text(current?.title ?? "")
                        .font(.headline)
                    if let index = currentIndex {
                        Text("\(index + 1) of \(panoramas.count)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
                Spacer()
                CircleButton(systemImage: "square.and.arrow.up") {
                    if let current {
                        sharePayload = SharePayload(items: [store.imageURL(for: current, in: projectID)])
                    }
                }
            }
            .padding(.horizontal)

            Spacer()

            if showMap, let layoutImage, hasPlacedPanoramas {
                HStack {
                    LayoutMiniMap(image: layoutImage, panoramas: panoramas, currentID: currentID) { id in
                        currentID = id
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            HStack(spacing: 20) {
                CircleButton(systemImage: "chevron.left") { step(-1) }
                    .disabled((currentIndex ?? 0) == 0)
                    .opacity((currentIndex ?? 0) == 0 ? 0.4 : 1)
                CircleButton(systemImage: motionEnabled ? "gyroscope" : "hand.draw",
                             highlighted: motionEnabled) {
                    motionEnabled.toggle()
                }
                CircleButton(systemImage: "scope") { resetToken += 1 }
                if layoutImage != nil, hasPlacedPanoramas {
                    CircleButton(systemImage: "map", highlighted: showMap) {
                        withAnimation { showMap.toggle() }
                    }
                }
                CircleButton(systemImage: "chevron.right") { step(1) }
                    .disabled((currentIndex ?? 0) >= panoramas.count - 1)
                    .opacity((currentIndex ?? 0) >= panoramas.count - 1 ? 0.4 : 1)
            }
            .padding(.bottom, 12)

            Text(motionEnabled ? "Move your phone to look around" : "Drag to look around · Pinch to zoom")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 8)
        }
    }

    private func step(_ delta: Int) {
        guard let index = currentIndex else { return }
        let next = index + delta
        guard panoramas.indices.contains(next) else { return }
        currentID = panoramas[next].id
    }

    private func loadImage() async {
        image = nil
        loadFailed = false
        guard let current else { loadFailed = true; return }
        let url = store.imageURL(for: current, in: projectID)
        let maxSize = Self.maxTextureSize
        let loaded = await Task.detached(priority: .userInitiated) {
            ImageProcessing.downsampledImage(at: url, maxPixelSize: maxSize)
        }.value
        guard !Task.isCancelled else { return }
        image = loaded
        loadFailed = loaded == nil
        resetToken += 1
    }
}

private struct CircleButton: View {
    let systemImage: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
                .foregroundStyle(highlighted ? Color.black : Color.white)
                .background(highlighted ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
        }
    }
}
