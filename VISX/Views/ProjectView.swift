import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A project: an interactive tour (floors + 360° views), drawings and renders.
/// Opens in a clean view-only mode suitable for clients; "Edit" reveals all authoring tools.
@MainActor
struct ProjectView: View {
    enum Section: Hashable, CaseIterable {
        case tour, drawings, renders
        var title: String {
            switch self {
            case .tour: return "360° Tour"
            case .drawings: return "Drawings"
            case .renders: return "Renders"
            }
        }
    }

    private struct ViewerTarget: Identifiable { let id: Panorama.ID }

    @EnvironmentObject private var store: ProjectStore
    let projectID: Project.ID

    @State private var section: Section = .tour
    @State private var isEditing = false
    @State private var selectedFloorID: Floor.ID?
    @State private var viewerTarget: ViewerTarget?

    @State private var importTarget: ImportTarget?
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isWorking = false

    @State private var editingDetails = false
    @State private var nameDraft = ""
    @State private var subtitleDraft = ""
    @State private var sharePayload: SharePayload?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                content(for: project)
            } else {
                EmptyStateView(systemImage: "questionmark.folder", title: "Project not found",
                               message: "This project may have been deleted.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(Brand.background.ignoresSafeArea())
        .toolbar { toolbar }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoSelection,
                      maxSelectionCount: allowsMultipleSelection ? nil : 1, matching: .images)
        .onChange(of: photoSelection) { items in
            guard !items.isEmpty else { return }
            importPhotos(items)
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: allowedFileTypes,
                      allowsMultipleSelection: allowsMultipleSelection) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .fullScreenCover(item: $viewerTarget) { target in
            PanoramaViewerView(projectID: projectID, startID: target.id, isEditing: isEditing)
                .environmentObject(store)
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .alert("Project Details", isPresented: $editingDetails) {
            TextField("Name", text: $nameDraft)
            TextField("Location or client", text: $subtitleDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.updateProject(projectID, name: nameDraft, subtitle: subtitleDraft) }
        }
        .errorAlert($errorMessage)
        .overlay {
            if isWorking {
                ProgressView()
                    .controlSize(.large)
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func content(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            hero(for: project)
            UnderlineTabs(items: Section.allCases, selection: $section) { $0.title }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            Rectangle().fill(Brand.hairline).frame(height: 0.5)

            switch section {
            case .tour:
                TourView(
                    project: project,
                    isEditing: isEditing,
                    selectedFloorID: $selectedFloorID,
                    onImport: { requestImport($0, $1) },
                    onOpen: { viewerTarget = ViewerTarget(id: $0) }
                )
            case .drawings:
                DocumentsView(project: project, kind: .drawing, isEditing: isEditing) {
                    requestImport(.documents(.drawing), $0)
                }
            case .renders:
                DocumentsView(project: project, kind: .render, isEditing: isEditing) {
                    requestImport(.documents(.render), $0)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            if selectedFloorID == nil || project.floor(selectedFloorID!) == nil {
                selectedFloorID = project.floors.first?.id
            }
            applyLaunchScreen(project)
        }
    }

    /// Cover image under the (transparent) navigation bar with the project name set over it.
    private func hero(for project: Project) -> some View {
        Color.clear
            .frame(height: section == .tour ? 210 : 280)
            .frame(maxWidth: .infinity)
            .background {
                if let cover = project.coverFileName {
                    ThumbnailView(url: store.fileURL(cover, in: project.id))
                } else {
                    LinearGradient(colors: [Brand.surfaceRaised, Brand.background], startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay { ImageScrim(strength: 1) }
            .overlay(alignment: .top) {
                // Keeps the status bar and navigation buttons legible over bright images.
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if !project.subtitle.isEmpty {
                        Eyebrow(project.subtitle, color: Brand.textPrimary.opacity(0.75), size: 10)
                    }
                    Text(project.name)
                        .font(.display(34))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
            .clipped()
            .animation(.easeInOut(duration: 0.25), value: section)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if isEditing {
                Button {
                    let project = store.project(id: projectID)
                    nameDraft = project?.name ?? ""
                    subtitleDraft = project?.subtitle ?? ""
                    editingDetails = true
                } label: {
                    Label("Project Details", systemImage: "info.circle")
                }
            } else {
                Button { shareProject() } label: {
                    Label("Share Project", systemImage: "square.and.arrow.up")
                }
            }
            Button(isEditing ? "Done" : "Edit") {
                withAnimation { isEditing.toggle() }
            }
            .fontWeight(isEditing ? .semibold : .regular)
        }
    }

    /// Demo / screenshot mode: open a specific part of the project.
    private func applyLaunchScreen(_ project: Project) {
        switch LaunchOptions.screen {
        case "drawings": section = .drawings
        case "renders": section = .renders
        case "edit": isEditing = true
        case "viewer":
            if let room = project.panoramas.first(where: { !$0.links.isEmpty }) {
                viewerTarget = ViewerTarget(id: room.id)
            }
        default: break
        }
    }

    // MARK: - Importing

    private var allowsMultipleSelection: Bool {
        if case .plan = importTarget { return false }
        return true
    }

    private var allowedFileTypes: [UTType] {
        if case .panoramas = importTarget { return [.image] }
        return [.image, .pdf]
    }

    private func requestImport(_ target: ImportTarget, _ source: ImportSource) {
        importTarget = target
        switch source {
        case .photos: showingPhotoPicker = true
        case .files: showingFileImporter = true
        }
    }

    private func save(_ data: Data, name: String) throws {
        switch importTarget {
        case .panoramas(let floorID):
            try store.addPanorama(imageData: data, title: name, floorID: floorID, to: projectID)
        case .plan(let floorID):
            try store.setPlan(data: data, for: floorID, in: projectID)
        case .documents(let kind):
            try store.addDocument(data: data, title: name, kind: kind, to: projectID)
        case nil:
            break
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        isWorking = true
        Task {
            var failures = 0
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { failures += 1; continue }
                    try save(data, name: "")
                } catch {
                    failures += 1
                }
            }
            photoSelection = []
            isWorking = false
            if failures > 0 { errorMessage = "\(failures) item\(failures == 1 ? "" : "s") could not be added." }
        }
    }

    private func importFiles(_ urls: [URL]) {
        isWorking = true
        Task {
            var failures = 0
            var lastError: Error?
            for url in urls {
                await Task.yield() // Let the progress indicator appear between files.
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    try save(try Data(contentsOf: url), name: url.deletingPathExtension().lastPathComponent)
                } catch {
                    failures += 1
                    lastError = error
                }
            }
            isWorking = false
            if failures == 1, let lastError {
                errorMessage = lastError.localizedDescription
            } else if failures > 1 {
                errorMessage = "\(failures) files could not be added."
            }
        }
    }

    private func shareProject() {
        isWorking = true
        Task {
            await Task.yield()
            defer { isWorking = false }
            do {
                sharePayload = SharePayload(items: [try store.exportArchive(for: projectID)])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
