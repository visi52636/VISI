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
    @State private var isLoadingSample = false

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 20)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.projects.isEmpty {
                    VStack(spacing: 0) {
                        header
                        EmptyStateView(
                        systemImage: "building.2",
                        title: "No projects yet",
                        message: "Create a project to add floor plans, 360° views, drawings and renders. Projects shared with you open here too."
                    ) {
                        VStack(spacing: 12) {
                            Button("New Project") { startNewProject() }
                                .buttonStyle(.primary)
                            Button("Try Sample Project") { loadSample() }
                                .buttonStyle(.secondary)
                        }
                        }
                    }
                } else {
                    ScrollView {
                        header
                        LazyVGrid(columns: columns, spacing: 20) {
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
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(Brand.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Project.ID.self) { id in
                ProjectView(projectID: id)
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
            .overlay {
                if isLoadingSample {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Preparing sample…").font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .onAppear {
                // Demo / screenshot mode: jump straight into the first project.
                if let screen = LaunchOptions.screen, screen != "projects", path.isEmpty, let first = store.projects.first {
                    path = [first.id]
                }
            }
        }
    }

    /// Studio wordmark with the app's actions; replaces the standard navigation bar.
    private var header: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .center) {
                BrandMark(height: 24)
                Spacer()
                Button { showingImporter = true } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 17, weight: .light))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Open Shared Project")
                Menu {
                    Button { startNewProject() } label: { Label("New Project", systemImage: "plus") }
                    Button { loadSample() } label: { Label("Add Sample Project", systemImage: "sparkles") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .light))
                        .frame(width: 40, height: 40)
                } primaryAction: {
                    startNewProject()
                }
                .accessibilityLabel("New Project")
            }
            .foregroundStyle(Brand.textPrimary)
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Projects")
                Spacer()
                Eyebrow(Brand.appName, color: Brand.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private func startNewProject() {
        newName = ""
        newSubtitle = ""
        showingNewProject = true
    }

    private func loadSample() {
        isLoadingSample = true
        Task {
            // Give the progress indicator a moment to appear; generating the sample takes a few seconds.
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let id = DemoContent.install(in: store) {
                path = [id]
            }
            isLoadingSample = false
        }
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
        ThumbnailView(url: project.coverFileName.map { store.fileURL($0, in: project.id) })
            .aspectRatio(4 / 5, contentMode: .fit)
            .overlay { ImageScrim() }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    if !project.subtitle.isEmpty {
                        Eyebrow(project.subtitle, color: Brand.textPrimary.opacity(0.75), size: 10)
                    }
                    Text(project.name)
                        .font(.display(32))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Rectangle().fill(Brand.accent).frame(width: 18, height: 1.5)
                        Eyebrow(summary, color: Brand.textSecondary, size: 9.5)
                    }
                    .padding(.top, 2)
                }
                .padding(22)
            }
            .clipShape(RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
    }

    private var summary: String {
        func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        return [
            count(project.floors.count, "floor"),
            count(project.panoramas.count, "view"),
            count(project.documents.count, "file")
        ].joined(separator: " · ")
    }
}
