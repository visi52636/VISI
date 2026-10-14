import SwiftUI
import PhotosUI

@MainActor
struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: Project.ID

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var isImporting = false
    @State private var sharePayload: SharePayload?
    @State private var viewerSelection: Panorama.ID?
    @State private var renamingProject = false
    @State private var renamingPanorama: Panorama?
    @State private var nameDraft = ""
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                content(for: project)
                    .navigationTitle(project.name)
            } else {
                Text("This project no longer exists.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { items in
            guard !items.isEmpty else { return }
            importPhotos(items)
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: Binding(
            get: { viewerSelection.map(ViewerTarget.init) },
            set: { viewerSelection = $0?.id }
        )) { target in
            PanoramaViewerView(projectID: projectID, initialPanoramaID: target.id)
                .environmentObject(store)
        }
        .alert("Rename Project", isPresented: $renamingProject) {
            TextField("Project name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.renameProject(projectID, to: nameDraft) }
        }
        .alert("Rename Panorama", isPresented: Binding(
            get: { renamingPanorama != nil },
            set: { if !$0 { renamingPanorama = nil } }
        )) {
            TextField("Title", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let panorama = renamingPanorama {
                    store.renamePanorama(panorama.id, in: projectID, to: nameDraft)
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay {
            if isImporting {
                ProgressView("Working…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    @ViewBuilder
    private func content(for project: Project) -> some View {
        if project.panoramas.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                Text("Add Your First Panorama")
                    .font(.title3.bold())
                Text("Import equirectangular 360° images (2:1 ratio) from your Photos library or the Files app.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                HStack {
                    Button { showingPhotoPicker = true } label: { Label("Photos", systemImage: "photo.on.rectangle") }
                    Button { showingFileImporter = true } label: { Label("Files", systemImage: "folder") }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                if !project.notes.isEmpty {
                    Text(project.notes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(project.panoramas) { panorama in
                        Button {
                            viewerSelection = panorama.id
                        } label: {
                            PanoramaTile(url: store.thumbnailURL(for: panorama, in: projectID), title: panorama.title)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { contextMenu(for: panorama) }
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for panorama: Panorama) -> some View {
        Button {
            viewerSelection = panorama.id
        } label: { Label("View in 360°", systemImage: "view.3d") }
        Button {
            sharePayload = SharePayload(items: [store.imageURL(for: panorama, in: projectID)])
        } label: { Label("Share Image", systemImage: "square.and.arrow.up") }
        Button {
            nameDraft = panorama.title
            renamingPanorama = panorama
        } label: { Label("Rename", systemImage: "pencil") }
        Button(role: .destructive) {
            store.deletePanorama(panorama.id, from: projectID)
        } label: { Label("Delete", systemImage: "trash") }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                shareProject()
            } label: {
                Label("Share Project", systemImage: "square.and.arrow.up")
            }
            .disabled(store.project(id: projectID)?.panoramas.isEmpty ?? true)

            Menu {
                Button { showingPhotoPicker = true } label: { Label("Add from Photos", systemImage: "photo.on.rectangle") }
                Button { showingFileImporter = true } label: { Label("Add from Files", systemImage: "folder") }
                Divider()
                Button {
                    nameDraft = store.project(id: projectID)?.name ?? ""
                    renamingProject = true
                } label: { Label("Rename Project", systemImage: "pencil") }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }

    // MARK: - Actions

    private func importPhotos(_ items: [PhotosPickerItem]) {
        isImporting = true
        Task {
            var failures = 0
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { failures += 1; continue }
                    try store.addPanorama(imageData: data, title: "", to: projectID)
                } catch {
                    failures += 1
                }
            }
            photoSelection = []
            isImporting = false
            if failures > 0 {
                errorMessage = "\(failures) image\(failures == 1 ? "" : "s") could not be imported."
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        isImporting = true
        Task {
            var failures = 0
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    try store.addPanorama(imageData: data, title: url.deletingPathExtension().lastPathComponent, to: projectID)
                } catch {
                    failures += 1
                }
            }
            isImporting = false
            if failures > 0 {
                errorMessage = "\(failures) file\(failures == 1 ? "" : "s") could not be imported."
            }
        }
    }

    private func shareProject() {
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let url = try store.exportArchive(for: projectID)
                sharePayload = SharePayload(items: [url])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ViewerTarget: Identifiable {
    let id: Panorama.ID
}

private struct PanoramaTile: View {
    let url: URL
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(url: url)
                .aspectRatio(2, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "rotate.3d")
                        .font(.caption.bold())
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
    }
}
