import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A shareable VIS X project file (`.visx`). Declared in Info.plist.
    static let visxProject = UTType(exportedAs: "com.visx.project")
}

@main
@MainActor
struct VISXApp: App {
    @StateObject private var store = ProjectStore()
    @State private var importError: String?
    @State private var importedProjectName: String?

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(.white)
                .onOpenURL { url in
                    // Called when a .visx file is opened from AirDrop, Messages, Mail or Files.
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
