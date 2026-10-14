import SwiftUI
import QuickLook

/// Grid of drawings or renders. Tapping opens a full-screen, swipeable, zoomable preview (images and PDFs).
@MainActor
struct DocumentsView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project
    let kind: ProjectDocument.Kind
    let isEditing: Bool
    let onImport: (ImportSource) -> Void

    @State private var previewURL: URL?
    @State private var renaming: ProjectDocument?
    @State private var toDelete: ProjectDocument?
    @State private var nameDraft = ""

    private var documents: [ProjectDocument] { project.documents(of: kind) }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: kind == .render ? 320 : 160), spacing: 16)] }
    private var aspectRatio: CGFloat { kind == .render ? 1.5 : 1.414 }

    var body: some View {
        Group {
            if documents.isEmpty {
                EmptyStateView(
                    systemImage: kind == .drawing ? "doc.text" : "photo.on.rectangle.angled",
                    title: "No \(kind.title.lowercased()) yet",
                    message: isEditing
                        ? (kind == .drawing ? "Add plans, sections and elevations as PDFs or images." : "Add renders and visualisations of the project.")
                        : "Nothing has been added here yet."
                ) {
                    if isEditing { ImportButtons(onSelect: onImport, filesLabel: "Files / PDF") }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(documents) { document in
                            Button {
                                previewURL = store.fileURL(document.fileName, in: project.id)
                            } label: {
                                ImageTile(
                                    url: store.fileURL(document.thumbnailFileName, in: project.id),
                                    title: document.title,
                                    aspectRatio: aspectRatio,
                                    fit: kind == .drawing
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if isEditing {
                                    Button {
                                        nameDraft = document.title
                                        renaming = document
                                    } label: { Label("Rename", systemImage: "pencil") }
                                    Button(role: .destructive) { toDelete = document } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                        if isEditing {
                            ImportMenu(onSelect: onImport) {
                                AddTile(title: "Add \(kind.singular.lowercased())", aspectRatio: aspectRatio)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .quickLookPreview($previewURL, in: documents.map { store.fileURL($0.fileName, in: project.id) })
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let document = renaming { store.renameDocument(document.id, in: project.id, to: nameDraft) }
            }
        }
        .confirmationDialog("Delete \"\(toDelete?.title ?? "")\"?",
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let document = toDelete { store.deleteDocument(document.id, from: project.id) }
            }
        }
    }
}
