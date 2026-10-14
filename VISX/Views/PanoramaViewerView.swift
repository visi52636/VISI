import SwiftUI

/// Full-screen 360° viewer. Walk from room to room with in-scene hotspots or the floor plan mini-map.
/// In edit mode, hotspots ("links") to other rooms can be added where the user is looking.
@MainActor
struct PanoramaViewerView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    let projectID: Project.ID
    let isEditing: Bool

    @State private var currentID: Panorama.ID
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var motionEnabled = false
    @State private var resetToken = 0
    @State private var controlsVisible = true
    @State private var showMap = true
    @State private var isPlacingLink = false
    @State private var pendingDirection: (yaw: Double, pitch: Double)?
    @State private var showingLinkPicker = false
    @State private var selectedLink: PanoramaLink?
    @State private var sceneController = PanoramaSceneController()

    /// Maximum texture width; 8192 px keeps detail while staying within GPU and memory limits.
    private static let maxTextureSize = 8192

    init(projectID: Project.ID, startID: Panorama.ID, isEditing: Bool) {
        self.projectID = projectID
        self.isEditing = isEditing
        _currentID = State(initialValue: startID)
    }

    private var project: Project? { store.project(id: projectID) }
    private var current: Panorama? { project?.panorama(currentID) }

    private var hotspots: [SceneHotspot] {
        guard let project, let current else { return [] }
        return current.links.compactMap { link in
            guard let target = project.panorama(link.targetID) else { return nil }
            return SceneHotspot(id: link.id, yaw: link.yaw, pitch: link.pitch, label: target.title)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                PanoramaSceneView(
                    image: image,
                    hotspots: hotspots,
                    motionEnabled: $motionEnabled,
                    resetToken: resetToken,
                    controller: sceneController,
                    onHotspotTap: { handleHotspotTap($0) },
                    onBackgroundTap: { withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() } }
                )
                .ignoresSafeArea()
            } else if loadFailed {
                Label("This 360° view could not be loaded.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            }

            if isLoading {
                ProgressView().tint(.white).controlSize(.large)
            }

            if isPlacingLink {
                crosshair
            }

            if controlsVisible || isPlacingLink {
                overlayControls
                    .transition(.opacity)
            }
        }
        .statusBarHidden(!controlsVisible)
        .task(id: currentID) { await loadImage() }
        .sheet(isPresented: $showingLinkPicker) {
            if let project {
                LinkTargetPicker(project: project, excluding: currentID) { targetID in
                    if let direction = pendingDirection {
                        store.addLink(from: currentID, to: targetID, yaw: direction.yaw, pitch: direction.pitch, in: projectID)
                    }
                    pendingDirection = nil
                    isPlacingLink = false
                }
                .environmentObject(store)
            }
        }
        .confirmationDialog(
            linkTitle(selectedLink),
            isPresented: Binding(get: { selectedLink != nil }, set: { if !$0 { selectedLink = nil } }),
            titleVisibility: .visible
        ) {
            if let link = selectedLink {
                Button("Go There") { go(to: link.targetID) }
                Button("Remove Link", role: .destructive) {
                    store.removeLink(link.id, from: currentID, in: projectID)
                }
            }
        }
    }

    // MARK: - Overlay

    private var overlayControls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                RoundButton(systemImage: "xmark") { dismiss() }
                Spacer(minLength: 0)
                VStack(spacing: 1) {
                    Text(current?.title ?? "")
                        .font(.subheadline.weight(.semibold))
                    if let floor = current.flatMap({ project?.floor($0.floorID) }) {
                        Text(floor.name)
                            .font(.caption)
                            .opacity(0.7)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.35), in: Capsule())
                Spacer(minLength: 0)
                RoundButton(systemImage: motionEnabled ? "iphone.radiowaves.left.and.right" : "iphone",
                            isActive: motionEnabled) {
                    motionEnabled.toggle()
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            if isPlacingLink {
                linkPlacementCard
            } else {
                HStack(alignment: .bottom) {
                    if showMap, let project, let current, mapAvailable(project, current) {
                        TourMiniMap(project: project, currentID: currentID) { go(to: $0) }
                            .environmentObject(store)
                    }
                    Spacer(minLength: 12)
                    VStack(spacing: 12) {
                        if isEditing {
                            RoundButton(systemImage: "link.badge.plus") {
                                motionEnabled = false
                                isPlacingLink = true
                            }
                        }
                        if let project, let current, mapAvailable(project, current) {
                            RoundButton(systemImage: "map", isActive: showMap) {
                                withAnimation(.easeInOut(duration: 0.2)) { showMap.toggle() }
                            }
                        }
                        RoundButton(systemImage: "scope") { resetToken += 1 }
                    }
                }
                .padding()
            }
        }
    }

    private var crosshair: some View {
        ZStack {
            Circle().stroke(.white, lineWidth: 2).frame(width: 34, height: 34)
            Circle().fill(.white).frame(width: 5, height: 5)
        }
        .shadow(radius: 3)
        .allowsHitTesting(false)
    }

    private var linkPlacementCard: some View {
        VStack(spacing: 12) {
            Text("Turn to face the doorway or stairs, then add the link.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Cancel") { isPlacingLink = false }
                    .buttonStyle(.bordered)
                Button("Link Here") {
                    pendingDirection = sceneController.currentDirection()
                    showingLinkPicker = pendingDirection != nil
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding()
    }

    // MARK: - Actions

    private func mapAvailable(_ project: Project, _ current: Panorama) -> Bool {
        project.floors.contains { $0.planFileName != nil }
    }

    private func linkTitle(_ link: PanoramaLink?) -> String {
        guard let link, let target = project?.panorama(link.targetID) else { return "" }
        return "Link to \(target.title)"
    }

    private func handleHotspotTap(_ linkID: UUID) {
        guard let link = current?.links.first(where: { $0.id == linkID }) else { return }
        if isEditing {
            selectedLink = link
        } else {
            go(to: link.targetID)
        }
    }

    private func go(to panoramaID: Panorama.ID) {
        guard panoramaID != currentID, project?.panorama(panoramaID) != nil else { return }
        currentID = panoramaID
    }

    private func loadImage() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        guard let current else { loadFailed = true; return }
        let url = store.fileURL(current.imageFileName, in: projectID)
        let maxSize = Self.maxTextureSize
        let loaded = await Task.detached(priority: .userInitiated) {
            ImageProcessing.downsampledImage(at: url, maxPixelSize: maxSize)
        }.value
        guard !Task.isCancelled else { return }
        // Keep showing the previous room until the next one is ready, then swap and face forward.
        image = loaded
        loadFailed = loaded == nil
        resetToken += 1
    }
}

/// Circular translucent button used over the panorama.
struct RoundButton: View {
    let systemImage: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 46, height: 46)
                .foregroundStyle(isActive ? Color.black : Color.white)
                .background(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.black.opacity(0.35)), in: Circle())
        }
    }
}

/// Floor plan card inside the viewer. Highlights where you are; tap a pin to walk there.
/// Expanded, it also lets you switch floors.
@MainActor
struct TourMiniMap: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project
    let currentID: Panorama.ID
    let onSelect: (Panorama.ID) -> Void

    @State private var expanded = false
    @State private var shownFloorID: Floor.ID?

    private var currentFloorID: Floor.ID? { project.panorama(currentID)?.floorID }
    private var floorsWithPlans: [Floor] { project.floors.filter { $0.planFileName != nil } }
    private var shownFloor: Floor? {
        let id = shownFloorID ?? currentFloorID
        return floorsWithPlans.first { $0.id == id } ?? floorsWithPlans.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if expanded && floorsWithPlans.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(floorsWithPlans) { floor in
                                Button { shownFloorID = floor.id } label: {
                                    Text(floor.name)
                                        .font(.caption.weight(floor.id == shownFloor?.id ? .semibold : .regular))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .foregroundStyle(floor.id == shownFloor?.id ? Color.white : Color.primary)
                                        .background(floor.id == shownFloor?.id ? Color.black : Color(.secondarySystemFill), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    Text(shownFloor?.name ?? "")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.primary)

            if let floor = shownFloor, let planName = floor.planFileName {
                AsyncPlanImage(url: store.fileURL(planName, in: project.id), maxPixelSize: 2048) { image in
                    PlanCanvas(
                        image: image,
                        panoramas: project.panoramas(on: floor.id),
                        highlightedID: currentID,
                        showLabels: expanded,
                        pinSize: expanded ? 18 : 11,
                        onPinTap: { onSelect($0.id) }
                    )
                }
                .frame(width: expanded ? 330 : 150, height: expanded ? 260 : 110)
            }
        }
        .padding(10)
        .frame(width: expanded ? 350 : 170)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .light)
        .onChange(of: currentFloorID) { _ in shownFloorID = nil }
    }
}

/// Sheet to choose which room a new link leads to, grouped by floor.
@MainActor
struct LinkTargetPicker: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let project: Project
    let excluding: Panorama.ID
    let onSelect: (Panorama.ID) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(project.floors) { floor in
                    let rooms = project.panoramas(on: floor.id).filter { $0.id != excluding }
                    if !rooms.isEmpty {
                        Section(floor.name) {
                            ForEach(rooms) { room in
                                Button {
                                    onSelect(room.id)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        ThumbnailView(url: store.fileURL(room.thumbnailFileName, in: project.id))
                                            .frame(width: 64, height: 40)
                                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        Text(room.title)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
