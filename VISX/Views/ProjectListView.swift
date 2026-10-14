import SwiftUI

@MainActor
struct ProjectListView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var path: [Project.ID] = []
    @State private var showingNewProject = false
    @State private var newName = ""
    @State private var newSubtitle = ""
    @State private var showingImporter = false
    @State private var projectToDelete: Project?
    @State private var sharePayload: SharePayload?
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 20)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.projects.isEmpty {
                    EmptyStateView(
                        systemImage: "building.2",
                        title: "No projects yet",
                        message: "Create a project to add floor plans, 360° views, drawings and renders. Projects shared with you open here too."
                    ) {
                        Button("New Project") { startNewProject() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(store.projects) { project in
                                NavigationLink(value: project.id) {
                                    ProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { share(project) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                                    Button(role: .destructive) { projectToDelete = project } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: Project.ID.self) { id in
                ProjectView(projectID: id)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showingImporter = true } label: {
                        Label("Open Shared Project", systemImage: "tray.and.arrow.down")
                    }
                    Button { startNewProject() } label: {
                        Label("New Project", systemImage: "plus")
                    }
                }
            }
            .alert("New Project", isPresented: $showingNewProject) {
                TextField("Name", text: $newName)
                TextField("Location or client (optional)", text: $newSubtitle)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let project = store.createProject(name: newName, subtitle: newSubtitle)
                    path.append(project.id)
                }
            }
            .confirmationDialog(
                "Delete \"\(projectToDelete?.name ?? "")\"?",
                isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Project", role: .destructive) {
                    if let project = projectToDelete { store.deleteProject(project.id) }
                }
            } message: {
                Text("All floors, 360° views, drawings and renders in this project will be removed from this device.")
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.visxProject]) { result in
                do {
                    let project = try store.importArchive(from: result.get())
                    path.append(project.id)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.items)
                    .presentationDetents([.medium, .large])
            }
            .errorAlert($errorMessage)
            .onAppear {
                // Demo / screenshot mode: jump straight into the first project.
                if let screen = LaunchOptions.screen, screen != "projects", path.isEmpty, let first = store.projects.first {
                    path = [first.id]
                }
            }
        }
    }

    private func startNewProject() {
        newName = ""
        newSubtitle = ""
        showingNewProject = true
    }

    private func share(_ project: Project) {
        do {
            sharePayload = SharePayload(items: [try store.exportArchive(for: project.id)])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
private struct ProjectCard: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ThumbnailView(url: project.coverFileName.map { store.fileURL($0, in: project.id) })
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.headline)
                if !project.subtitle.isEmpty {
                    Text(project.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var summary: String {
        func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        return [
            count(project.floors.count, "floor"),
            count(project.panoramas.count, "360° view"),
            count(project.documents.count, "file")
        ].joined(separator: " · ")
    }
}
