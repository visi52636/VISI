import SwiftUI

/// Floors with their plans and 360° views. Tap a pin (or a room below the plan) to step inside.
@MainActor
struct TourView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project
    let isEditing: Bool
    @Binding var selectedFloorID: Floor.ID?
    let onImport: (ImportTarget, ImportSource) -> Void
    let onOpen: (Panorama.ID) -> Void

    @State private var placingID: Panorama.ID?
    @State private var showingAddFloor = false
    @State private var showingCustomFloor = false
    @State private var renamingFloor: Floor?
    @State private var floorToDelete: Floor?
    @State private var renamingRoom: Panorama?
    @State private var roomToDelete: Panorama?
    @State private var nameDraft = ""

    private static let floorPresets = ["Basement", "Ground Floor", "First Floor", "Second Floor",
                                       "Third Floor", "Roof", "Site / Exterior"]

    private var floor: Floor? {
        project.floors.first { $0.id == selectedFloorID } ?? project.floors.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if project.floors.count > 1 || isEditing {
                floorBar
            }
            if let floor {
                floorContent(floor)
            } else {
                EmptyStateView(systemImage: "square.stack.3d.up", title: "No floors",
                               message: isEditing ? "Add a floor to start building the tour." : "This project has no 360° tour yet.") {
                    if isEditing {
                        Button("Add Floor") { showingAddFloor = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .onChange(of: isEditing) { editing in
            if !editing { placingID = nil }
        }
        .onChange(of: selectedFloorID) { _ in placingID = nil }
        .confirmationDialog("Add Floor", isPresented: $showingAddFloor, titleVisibility: .visible) {
            ForEach(Self.floorPresets.filter { name in !project.floors.contains { $0.name == name } }, id: \.self) { name in
                Button(name) { addFloor(name) }
            }
            Button("Custom Name…") {
                nameDraft = ""
                showingCustomFloor = true
            }
        }
        .alert("New Floor", isPresented: $showingCustomFloor) {
            TextField("Floor name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Add") { addFloor(nameDraft) }
        }
        .alert("Rename Floor", isPresented: isPresent($renamingFloor)) {
            TextField("Floor name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let floor = renamingFloor { store.renameFloor(floor.id, in: project.id, to: nameDraft) }
            }
        }
        .alert("Rename 360° View", isPresented: isPresent($renamingRoom)) {
            TextField("Room name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let room = renamingRoom { store.renamePanorama(room.id, in: project.id, to: nameDraft) }
            }
        }
        .confirmationDialog("Delete \"\(floorToDelete?.name ?? "")\"?", isPresented: isPresent($floorToDelete),
                            titleVisibility: .visible) {
            Button("Delete Floor", role: .destructive) {
                if let floor = floorToDelete {
                    store.deleteFloor(floor.id, in: project.id)
                    selectedFloorID = project.floors.first { $0.id != floor.id }?.id
                }
            }
        } message: {
            Text("Its plan and all its 360° views will be deleted.")
        }
        .confirmationDialog("Delete \"\(roomToDelete?.title ?? "")\"?", isPresented: isPresent($roomToDelete),
                            titleVisibility: .visible) {
            Button("Delete 360° View", role: .destructive) {
                if let room = roomToDelete { store.deletePanorama(room.id, from: project.id) }
            }
        }
    }

    // MARK: - Floors

    private var floorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(project.floors) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedFloorID = item.id }
                    } label: {
                        Chip(title: item.name, isSelected: item.id == floor?.id)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if isEditing { floorMenu(item) }
                    }
                }
                if isEditing {
                    Button { showingAddFloor = true } label: {
                        Label("Floor", systemImage: "plus")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func floorMenu(_ item: Floor) -> some View {
        Button {
            nameDraft = item.name
            renamingFloor = item
        } label: { Label("Rename", systemImage: "pencil") }
        Button { onImport(.plan(item.id), .files) } label: {
            Label(item.planFileName == nil ? "Add Plan from Files" : "Replace Plan from Files", systemImage: "doc")
        }
        Button { onImport(.plan(item.id), .photos) } label: {
            Label(item.planFileName == nil ? "Add Plan from Photos" : "Replace Plan from Photos", systemImage: "photo")
        }
        Button { store.moveFloor(item.id, in: project.id, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") }
        Button { store.moveFloor(item.id, in: project.id, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") }
        Button(role: .destructive) { floorToDelete = item } label: { Label("Delete Floor", systemImage: "trash") }
    }

    private func addFloor(_ name: String) {
        if let floor = store.addFloor(named: name, to: project.id) {
            selectedFloorID = floor.id
        }
    }

    // MARK: - Floor content

    @ViewBuilder
    private func floorContent(_ floor: Floor) -> some View {
        let rooms = project.panoramas(on: floor.id)
        if let planName = floor.planFileName {
            AsyncPlanImage(url: store.fileURL(planName, in: project.id)) { image in
                ZoomablePlanView(
                    image: image,
                    panoramas: rooms,
                    highlightedID: placingID,
                    isEditing: isEditing,
                    onTap: { point in place(at: point, rooms: rooms) },
                    onPinTap: { room in
                        if isEditing { placingID = room.id } else { onOpen(room.id) }
                    },
                    onPinMoved: { room, point in store.setPosition(point, for: room.id, in: project.id) }
                )
            }
            .background(Color(.systemGroupedBackground))
            if isEditing || !rooms.isEmpty {
                roomStrip(rooms, floor: floor, hasPlan: true)
            }
        } else if isEditing {
            EmptyStateView(systemImage: "map", title: "Add the \(floor.name) plan",
                           message: "Upload the plan as an image or PDF. Then add 360° views and place them on it.") {
                ImportButtons(onSelect: { onImport(.plan(floor.id), $0) }, filesLabel: "Files / PDF")
            }
            roomStrip(rooms, floor: floor, hasPlan: false)
        } else if rooms.isEmpty {
            EmptyStateView(systemImage: "cube.transparent", title: "Nothing here yet",
                           message: "This floor has no 360° views.")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 20) {
                    ForEach(rooms) { room in
                        Button { onOpen(room.id) } label: {
                            ImageTile(url: store.fileURL(room.thumbnailFileName, in: project.id), title: room.title, aspectRatio: 1.6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    private func roomStrip(_ rooms: [Panorama], floor: Floor, hasPlan: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            if isEditing && hasPlan && !rooms.isEmpty {
                Text(placementHint(rooms))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 10)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(rooms) { room in
                        ImageTile(
                            url: store.fileURL(room.thumbnailFileName, in: project.id),
                            title: room.title,
                            aspectRatio: 1.6,
                            isSelected: isEditing && room.id == placingID
                        )
                        .frame(width: 124)
                        .overlay(alignment: .topTrailing) {
                            if isEditing && hasPlan && room.layoutPosition == nil {
                                Image(systemName: "mappin.slash")
                                    .font(.caption2.weight(.semibold))
                                    .padding(5)
                                    .background(.regularMaterial, in: Circle())
                                    .padding(5)
                            }
                        }
                        .onTapGesture {
                            if isEditing && hasPlan { placingID = room.id } else { onOpen(room.id) }
                        }
                        .contextMenu { roomMenu(room) }
                    }
                    if isEditing {
                        ImportMenu(onSelect: { onImport(.panoramas(floor.id), $0) }) {
                            AddTile(title: "Add 360° view", aspectRatio: 1.6)
                                .frame(width: 124)
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func roomMenu(_ room: Panorama) -> some View {
        Button { onOpen(room.id) } label: { Label("Open", systemImage: "view.3d") }
        if isEditing {
            Button {
                nameDraft = room.title
                renamingRoom = room
            } label: { Label("Rename", systemImage: "pencil") }
            if room.layoutPosition != nil {
                Button { store.setPosition(nil, for: room.id, in: project.id) } label: {
                    Label("Remove from Plan", systemImage: "mappin.slash")
                }
            }
            Button(role: .destructive) { roomToDelete = room } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func placementHint(_ rooms: [Panorama]) -> String {
        if let id = placingID, let room = rooms.first(where: { $0.id == id }) {
            return "Tap the plan where “\(room.title)” was taken. Drag pins to adjust."
        }
        return "Select a 360° view below, then tap its position on the plan."
    }

    private func place(at point: LayoutPoint, rooms: [Panorama]) {
        guard isEditing, let id = placingID else { return }
        store.setPosition(point, for: id, in: project.id)
        // Move on to the next view that isn't on the plan yet (`rooms` is a snapshot from before this change).
        placingID = rooms.first { $0.id != id && $0.layoutPosition == nil }?.id
    }

    private func isPresent<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}
