import SwiftUI

@MainActor
struct ProjectListView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var path: [Project.ID] = []
    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var showingImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.projects.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.projects) { project in
                            NavigationLink(value: project.id) {
                                ProjectRow(project: project)
                            }
                        }
                        .onDelete(perform: store.deleteProjects)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: Project.ID.self) { id in
                ProjectDetailView(projectID: id)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Project", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newProjectName = ""
                        showingNewProject = true
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                }
            }
            .alert("New Project", isPresented: $showingNewProject) {
                TextField("Project name", text: $newProjectName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let project = store.createProject(name: newProjectName)
                    path.append(project.id)
                }
            } message: {
                Text("Give your 360° project a name.")
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.visiProject]) { result in
                do {
                    let project = try store.importArchive(from: result.get())
                    path.append(project.id)
                } catch {
                    errorMessage = error.localizedDescription
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pano.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("No Projects Yet")
                .font(.title2.bold())
            Text("Create a project, then add your 360° panoramas from Photos or Files. Projects you receive by AirDrop appear here too.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button {
                newProjectName = ""
                showingNewProject = true
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private struct ProjectRow: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: project.panoramas.first.map { store.thumbnailURL(for: $0, in: project.id) })
                .frame(width: 88, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.headline)
                Text("\(project.panoramas.count) panorama\(project.panoramas.count == 1 ? "" : "s") · \(project.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
