import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A shareable VISI project file (`.visiproj`). Declared in Info.plist.
    static let visiProject = UTType(exportedAs: "com.visi.project")
}

@main
@MainActor
struct VISIApp: App {
    @StateObject private var store = ProjectStore()
    @State private var importError: String?
    @State private var importedProjectName: String?

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environmentObject(store)
                .onOpenURL { url in
                    // Called when a .visiproj file is opened from AirDrop, Messages, Mail or Files.
                    do {
                        let project = try store.importArchive(from: url)
                        importedProjectName = project.name
                    } catch {
                        importError = error.localizedDescription
                    }
                    if url.path.contains("/Inbox/") {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                .alert("Project Imported", isPresented: Binding(
                    get: { importedProjectName != nil },
                    set: { if !$0 { importedProjectName = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("\"\(importedProjectName ?? "")\" was added to your projects.")
                }
                .alert("Import Failed", isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(importError ?? "")
                }
        }
    }
}
