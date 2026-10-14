import SwiftUI

/// Draws a floor plan with a pin for every placed 360° view.
struct PlanCanvas: View {
    let image: UIImage
    let panoramas: [Panorama]
    var highlightedID: Panorama.ID?
    var isEditing = false
    var showLabels = true
    var pinSize: CGFloat = 18
    var onTap: ((LayoutPoint) -> Void)?
    var onPinTap: ((Panorama) -> Void)?
    var onPinMoved: ((Panorama, LayoutPoint) -> Void)?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { value in
                                guard geo.size.width > 0, geo.size.height > 0 else { return }
                                onTap?(LayoutPoint(x: value.location.x / geo.size.width,
                                                   y: value.location.y / geo.size.height))
                            })
                        ForEach(panoramas) { panorama in
                            if let position = panorama.layoutPosition {
                                PlanPin(
                                    title: panorama.title,
                                    isHighlighted: panorama.id == highlightedID,
                                    isEditing: isEditing,
                                    showLabel: showLabels,
                                    size: pinSize,
                                    canvasSize: geo.size,
                                    position: position,
                                    onTap: { onPinTap?(panorama) },
                                    onMoved: { onPinMoved?(panorama, $0) }
                                )
                            }
                        }
                    }
                }
            }
    }
}

private struct PlanPin: View {
    let title: String
    let isHighlighted: Bool
    let isEditing: Bool
    let showLabel: Bool
    let size: CGFloat
    let canvasSize: CGSize
    let position: LayoutPoint
    let onTap: () -> Void
    let onMoved: (LayoutPoint) -> Void

    @GestureState private var dragOffset: CGSize = .zero

    private static let pinColor = Color(white: 0.1)
    private static let highlightColor = Color.orange

    var body: some View {
        let diameter = isHighlighted ? size * 1.25 : size
        Circle()
            .fill(isHighlighted ? Self.highlightColor : Self.pinColor)
            .overlay(Circle().stroke(.white, lineWidth: max(1.5, diameter * 0.14)))
            .overlay(Circle().fill(.white).frame(width: diameter * 0.3, height: diameter * 0.3))
            .frame(width: diameter, height: diameter)
            .background {
                if isHighlighted {
                    Circle()
                        .fill(Self.highlightColor.opacity(0.25))
                        .frame(width: diameter * 2.2, height: diameter * 2.2)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .overlay(alignment: .top) {
                if showLabel {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.92), in: Capsule())
                        .fixedSize()
                        .offset(y: diameter + 3)
                }
            }
            .contentShape(Circle().inset(by: -10))
            .position(x: position.x * canvasSize.width, y: position.y * canvasSize.height)
            .offset(dragOffset)
            .onTapGesture(perform: onTap)
            .gesture(dragGesture, including: isEditing ? GestureMask.all : [])
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
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

/// A plan that can be zoomed (pinch or buttons) and scrolled. Pins keep their size while zooming.
struct ZoomablePlanView: View {
    let image: UIImage
    let panoramas: [Panorama]
    var highlightedID: Panorama.ID?
    var isEditing = false
    var onTap: ((LayoutPoint) -> Void)?
    var onPinTap: ((Panorama) -> Void)?
    var onPinMoved: ((Panorama, LayoutPoint) -> Void)?

    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 16
            let available = CGSize(width: max(geo.size.width - inset * 2, 1), height: max(geo.size.height - inset * 2, 1))
            let fitted = Self.fittedSize(for: image.size, in: available)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                PlanCanvas(
                    image: image,
                    panoramas: panoramas,
                    highlightedID: highlightedID,
                    isEditing: isEditing,
                    onTap: onTap,
                    onPinTap: onPinTap,
                    onPinMoved: onPinMoved
                )
                .frame(width: fitted.width * zoom, height: fitted.height * zoom)
                .padding(inset)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { zoom = min(max(baseZoom * $0, 1), 6) }
                    .onEnded { _ in baseZoom = zoom }
            )
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    zoomButton("plus") { setZoom(zoom * 1.6) }
                    Divider().frame(width: 36)
                    zoomButton("minus") { setZoom(zoom / 1.6) }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(12)
            }
        }
    }

    private func zoomButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
        }
    }

    private func setZoom(_ value: CGFloat) {
        withAnimation(.easeInOut(duration: 0.25)) {
            zoom = min(max(value, 1), 6)
            baseZoom = zoom
        }
    }

    static func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

/// Loads a plan image off the main thread, downsampled for display.
struct AsyncPlanImage<Content: View>: View {
    let url: URL
    var maxPixelSize = 4096
    @ViewBuilder let content: (UIImage) -> Content

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                content(image)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            let size = maxPixelSize
            image = await Task.detached(priority: .userInitiated) {
                ImageProcessing.downsampledImage(at: url, maxPixelSize: size)
            }.value
        }
    }
}
