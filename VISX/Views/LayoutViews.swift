import SwiftUI

/// Draws a layout (floor plan / site plan) with a numbered marker for every placed panorama.
/// The marker number matches the panorama's position in the project.
struct LayoutCanvas: View {
    let image: UIImage
    let panoramas: [Panorama]
    var highlightedID: Panorama.ID?
    var isEditing = false
    var markerSize: CGFloat = 30
    var onTap: ((LayoutPoint) -> Void)?
    var onMarkerTap: ((Panorama) -> Void)?
    var onMarkerMoved: ((Panorama, LayoutPoint) -> Void)?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture().onEnded { value in
                                    guard geo.size.width > 0, geo.size.height > 0 else { return }
                                    onTap?(LayoutPoint(x: value.location.x / geo.size.width,
                                                       y: value.location.y / geo.size.height))
                                }
                            )
                        ForEach(Array(panoramas.enumerated()), id: \.element.id) { index, panorama in
                            if let position = panorama.layoutPosition {
                                LayoutMarker(
                                    number: index + 1,
                                    isHighlighted: panorama.id == highlightedID,
                                    isEditing: isEditing,
                                    size: markerSize,
                                    canvasSize: geo.size,
                                    position: position,
                                    onTap: { onMarkerTap?(panorama) },
                                    onMoved: { onMarkerMoved?(panorama, $0) }
                                )
                            }
                        }
                    }
                }
            }
    }
}

private struct LayoutMarker: View {
    let number: Int
    let isHighlighted: Bool
    let isEditing: Bool
    let size: CGFloat
    let canvasSize: CGSize
    let position: LayoutPoint
    let onTap: () -> Void
    let onMoved: (LayoutPoint) -> Void

    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        let diameter = isHighlighted ? size * 1.3 : size
        ZStack {
            if isHighlighted {
                Circle()
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(width: diameter * 1.9, height: diameter * 1.9)
            }
            Circle()
                .fill(isHighlighted ? Color.accentColor : Color.red)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(radius: 2)
                .frame(width: diameter, height: diameter)
            Text("\(number)")
                .font(.system(size: diameter * 0.45, weight: .bold))
                .foregroundStyle(.white)
        }
        .position(x: position.x * canvasSize.width, y: position.y * canvasSize.height)
        .offset(dragOffset)
        .onTapGesture(perform: onTap)
        .gesture(dragGesture, including: isEditing ? GestureMask.all : [])
        .accessibilityLabel("Panorama \(number)")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragOffset) { value, state, _ in state = value.translation }
            .onEnded { value in
                guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                onMoved(LayoutPoint(
                    x: position.x + value.translation.width / canvasSize.width,
                    y: position.y + value.translation.height / canvasSize.height
                ))
            }
    }
}

/// Loads a layout image off the main thread, downsampled for display.
struct LayoutImageLoader: View {
    let url: URL?
    var maxPixelSize = 4096
    let content: (UIImage) -> AnyView

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            let size = maxPixelSize
            image = await Task.detached(priority: .userInitiated) {
                ImageProcessing.downsampledImage(at: url, maxPixelSize: size)
            }.value
        }
    }
}

/// The "Layout" tab of a project: shows the plan with panorama positions and lets the user place them.
@MainActor
struct ProjectLayoutView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project
    let onAddLayoutFromPhotos: () -> Void
    let onAddLayoutFromFiles: () -> Void
    let onOpenPanorama: (Panorama.ID) -> Void

    @State private var isEditing = false
    @State private var placingID: Panorama.ID?
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var confirmingRemove = false

    private var placedCount: Int { project.panoramas.filter { $0.layoutPosition != nil }.count }

    var body: some View {
        if let url = store.layoutImageURL(for: project) {
            VStack(spacing: 0) {
                header
                LayoutImageLoader(url: url) { image in
                    AnyView(zoomableCanvas(image: image))
                }
                if isEditing {
                    placementStrip
                }
            }
            .confirmationDialog("Remove the layout and all panorama positions?",
                                isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove Layout", role: .destructive) {
                    isEditing = false
                    store.removeLayout(for: project.id)
                }
            }
        } else {
            emptyState
        }
    }

    private var header: some View {
        HStack {
            Text(isEditing
                 ? (placingID == nil ? "Select a panorama below, then tap its spot on the plan" : "Tap the plan to place it · drag markers to move")
                 : "\(placedCount) of \(project.panoramas.count) placed · tap a marker to view")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            if !isEditing {
                Menu {
                    Button { onAddLayoutFromPhotos() } label: { Label("Replace from Photos", systemImage: "photo.on.rectangle") }
                    Button { onAddLayoutFromFiles() } label: { Label("Replace from Files (Image or PDF)", systemImage: "folder") }
                    Button(role: .destructive) { confirmingRemove = true } label: { Label("Remove Layout", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            Button(isEditing ? "Done" : "Place") {
                isEditing.toggle()
                placingID = isEditing ? firstUnplacedID() : nil
            }
            .buttonStyle(.bordered)
            .disabled(project.panoramas.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func zoomableCanvas(image: UIImage) -> some View {
        GeometryReader { geo in
            let fitted = fittedSize(for: image.size, in: geo.size)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                LayoutCanvas(
                    image: image,
                    panoramas: project.panoramas,
                    highlightedID: placingID,
                    isEditing: isEditing,
                    onTap: { point in
                        guard isEditing, let id = placingID else { return }
                        store.setLayoutPosition(point, for: id, in: project.id)
                        placingID = nextUnplacedID(after: id)
                    },
                    onMarkerTap: { panorama in
                        if isEditing {
                            placingID = panorama.id
                        } else {
                            onOpenPanorama(panorama.id)
                        }
                    },
                    onMarkerMoved: { panorama, point in
                        store.setLayoutPosition(point, for: panorama.id, in: project.id)
                    }
                )
                .frame(width: fitted.width * zoom, height: fitted.height * zoom)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { zoom = min(max(baseZoom * $0, 1), 6) }
                    .onEnded { _ in baseZoom = zoom }
            )
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 8) {
                    zoomButton("plus.magnifyingglass") { setZoom(zoom * 1.5) }
                    zoomButton("minus.magnifyingglass") { setZoom(zoom / 1.5) }
                }
                .padding(12)
            }
        }
        .background(Color(.secondarySystemBackground))
    }

    private var placementStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(project.panoramas.enumerated()), id: \.element.id) { index, panorama in
                    let selected = panorama.id == placingID
                    VStack(spacing: 4) {
                        ThumbnailView(url: store.thumbnailURL(for: panorama, in: project.id))
                            .frame(width: 96, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
                            .overlay(alignment: .topLeading) {
                                Text("\(index + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(panorama.layoutPosition == nil ? Color.gray : Color.red, in: Circle())
                                    .padding(3)
                            }
                        Text(panorama.layoutPosition == nil ? "Not placed" : panorama.title)
                            .font(.caption2)
                            .foregroundStyle(panorama.layoutPosition == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .frame(width: 96)
                    }
                    .onTapGesture { placingID = panorama.id }
                    .contextMenu {
                        if panorama.layoutPosition != nil {
                            Button(role: .destructive) {
                                store.setLayoutPosition(nil, for: panorama.id, in: project.id)
                            } label: { Label("Remove from Layout", systemImage: "mappin.slash") }
                        }
                    }
                }
            }
            .padding()
        }
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Add a Layout")
                .font(.title3.bold())
            Text("Upload a floor plan or site plan (image or PDF), then place each panorama where it was taken. Tap a marker to jump straight into that 360° view.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            HStack {
                Button(action: onAddLayoutFromPhotos) { Label("Photos", systemImage: "photo.on.rectangle") }
                Button(action: onAddLayoutFromFiles) { Label("Files / PDF", systemImage: "folder") }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func zoomButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
        }
    }

    private func setZoom(_ value: CGFloat) {
        withAnimation {
            zoom = min(max(value, 1), 6)
            baseZoom = zoom
        }
    }

    private func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func firstUnplacedID() -> Panorama.ID? {
        project.panoramas.first { $0.layoutPosition == nil }?.id ?? project.panoramas.first?.id
    }

    private func nextUnplacedID(after id: Panorama.ID) -> Panorama.ID? {
        guard let index = project.panoramas.firstIndex(where: { $0.id == id }) else { return nil }
        // `project` is a snapshot, so the panorama just placed still reads as unplaced here — skip it.
        return project.panoramas[(index + 1)...].first { $0.layoutPosition == nil }?.id
            ?? project.panoramas[..<index].first { $0.layoutPosition == nil }?.id
    }
}

/// Small layout map shown inside the 360° viewer, highlighting the current panorama's position.
@MainActor
struct LayoutMiniMap: View {
    let image: UIImage
    let panoramas: [Panorama]
    let currentID: Panorama.ID
    let onSelect: (Panorama.ID) -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button {
                withAnimation(.spring()) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
            }
            LayoutCanvas(
                image: image,
                panoramas: panoramas,
                highlightedID: currentID,
                markerSize: expanded ? 24 : 14,
                onMarkerTap: { onSelect($0.id) }
            )
            .frame(maxWidth: expanded ? 340 : 150, maxHeight: expanded ? 340 : 150)
            .padding(4)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 4)
        }
    }
}
