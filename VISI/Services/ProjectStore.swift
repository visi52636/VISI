import Foundation
import SwiftUI

enum ProjectStoreError: LocalizedError {
    case notAnImage
    case invalidArchive
    case unsupportedArchiveVersion(Int)

    var errorDescription: String? {
        switch self {
        case .notAnImage: return "The selected file is not a supported image."
        case .invalidArchive: return "The file is not a valid VISI project."
        case .unsupportedArchiveVersion(let v): return "This project was created with a newer version of VISI (format \(v))."
        }
    }
}

/// Persists projects and their panorama images in the app's Documents directory.
///
/// Layout:
///   Documents/projects.json             – project index
///   Documents/Projects/<project-id>/    – image + thumbnail files for each panorama
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    private let fileManager = FileManager.default
    private let rootURL: URL
    private var indexURL: URL { rootURL.appendingPathComponent("projects.json") }
    private var projectsDirectory: URL { rootURL.appendingPathComponent("Projects", isDirectory: true) }

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        load()
    }

    // MARK: - Lookup

    func project(id: Project.ID) -> Project? {
        projects.first { $0.id == id }
    }

    func directory(for projectID: Project.ID) -> URL {
        projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    func imageURL(for panorama: Panorama, in projectID: Project.ID) -> URL {
        directory(for: projectID).appendingPathComponent(panorama.imageFileName)
    }

    func thumbnailURL(for panorama: Panorama, in projectID: Project.ID) -> URL {
        directory(for: projectID).appendingPathComponent(panorama.thumbnailFileName)
    }

    // MARK: - Projects

    @discardableResult
    func createProject(name: String, notes: String = "") -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(name: trimmed.isEmpty ? "Untitled Project" : trimmed, notes: notes)
        try? fileManager.createDirectory(at: directory(for: project.id), withIntermediateDirectories: true)
        projects.insert(project, at: 0)
        save()
        return project
    }

    func renameProject(_ projectID: Project.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].name = trimmed
        save()
    }

    func updateNotes(_ projectID: Project.ID, notes: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].notes = notes
        save()
    }

    func deleteProjects(at offsets: IndexSet) {
        for index in offsets {
            try? fileManager.removeItem(at: directory(for: projects[index].id))
        }
        projects.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Panoramas

    @discardableResult
    func addPanorama(imageData: Data, title: String, createdAt: Date = Date(), to projectID: Project.ID) throws -> Panorama {
        guard ImageProcessing.isImage(imageData) else { throw ProjectStoreError.notAnImage }
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { throw ProjectStoreError.invalidArchive }

        let folder = directory(for: projectID)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let id = UUID()
        let imageName = "\(id.uuidString).\(ImageProcessing.fileExtension(for: imageData))"
        let thumbName = "\(id.uuidString)_thumb.jpg"
        let imageURL = folder.appendingPathComponent(imageName)
        try imageData.write(to: imageURL, options: .atomic)
        if let thumb = ImageProcessing.thumbnailData(for: imageURL) {
            try thumb.write(to: folder.appendingPathComponent(thumbName), options: .atomic)
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let panorama = Panorama(
            id: id,
            title: trimmed.isEmpty ? "Panorama \(projects[index].panoramas.count + 1)" : trimmed,
            imageFileName: imageName,
            thumbnailFileName: thumbName,
            createdAt: createdAt
        )
        projects[index].panoramas.append(panorama)
        save()
        return panorama
    }

    func renamePanorama(_ panoramaID: Panorama.ID, in projectID: Project.ID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let p = projects.firstIndex(where: { $0.id == projectID }),
              let i = projects[p].panoramas.firstIndex(where: { $0.id == panoramaID }) else { return }
        projects[p].panoramas[i].title = trimmed
        save()
    }

    func deletePanorama(_ panoramaID: Panorama.ID, from projectID: Project.ID) {
        guard let p = projects.firstIndex(where: { $0.id == projectID }),
              let i = projects[p].panoramas.firstIndex(where: { $0.id == panoramaID }) else { return }
        let panorama = projects[p].panoramas[i]
        try? fileManager.removeItem(at: imageURL(for: panorama, in: projectID))
        try? fileManager.removeItem(at: thumbnailURL(for: panorama, in: projectID))
        projects[p].panoramas.remove(at: i)
        save()
    }

    // MARK: - Sharing

    /// Writes the whole project into a single `.visiproj` file in the temporary directory
    /// so it can be sent via AirDrop, Messages, Mail, Files, etc.
    func exportArchive(for projectID: Project.ID) throws -> URL {
        guard let project = self.project(id: projectID) else { throw ProjectStoreError.invalidArchive }
        let items = try project.panoramas.map { panorama in
            ProjectArchive.Item(
                title: panorama.title,
                createdAt: panorama.createdAt,
                imageData: try Data(contentsOf: imageURL(for: panorama, in: projectID))
            )
        }
        let archive = ProjectArchive(name: project.name, notes: project.notes, createdAt: project.createdAt, items: items)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(archive)

        let exportDir = fileManager.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? fileManager.removeItem(at: exportDir)
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let url = exportDir.appendingPathComponent("\(sanitizedFileName(project.name)).visiproj")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Imports a `.visiproj` file received from another device as a new project.
    @discardableResult
    func importArchive(from url: URL) throws -> Project {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let archive: ProjectArchive
        do {
            archive = try PropertyListDecoder().decode(ProjectArchive.self, from: data)
        } catch {
            throw ProjectStoreError.invalidArchive
        }
        guard archive.version <= ProjectArchive.formatVersion else {
            throw ProjectStoreError.unsupportedArchiveVersion(archive.version)
        }

        let project = createProject(name: uniqueName(for: archive.name), notes: archive.notes)
        for item in archive.items {
            try addPanorama(imageData: item.imageData, title: item.title, createdAt: item.createdAt, to: project.id)
        }
        return self.project(id: project.id) ?? project
    }

    // MARK: - Persistence

    private func load() {
        try? fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        projects = (try? decoder.decode([Project].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(projects) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func uniqueName(for name: String) -> String {
        let existing = Set(projects.map(\.name))
        guard existing.contains(name) else { return name }
        var counter = 2
        while existing.contains("\(name) (\(counter))") { counter += 1 }
        return "\(name) (\(counter))"
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "Project" : cleaned
    }
}
