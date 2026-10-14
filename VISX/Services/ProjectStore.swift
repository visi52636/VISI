import Foundation
import SwiftUI

enum ProjectStoreError: LocalizedError {
    case unsupportedFile
    case notFound
    case invalidArchive
    case unsupportedArchiveVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: return "This file type isn't supported. Use an image (JPG, PNG, HEIC) or a PDF."
        case .notFound: return "This item no longer exists."
        case .invalidArchive: return "The file is not a valid VIS X project."
        case .unsupportedArchiveVersion(let v): return "This project was made with a newer version of VIS X (format \(v)). Please update the app."
        }
    }
}

/// Persists projects and their files in the app's Documents directory.
///
/// Layout:
///   Documents/projects.json           – index of all projects
///   Documents/Projects/<project-id>/  – panoramas, thumbnails, plans, drawings and renders
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    static let defaultFloorName = "Ground Floor"

    private let fileManager = FileManager.default
    private let rootURL: URL
    private var indexURL: URL { rootURL.appendingPathComponent("projects.json") }
    private var projectsDirectory: URL { rootURL.appendingPathComponent("Projects", isDirectory: true) }

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        load()
        if LaunchOptions.isDemo {
            DemoContent.install(in: self)
        }
    }

    // MARK: - Lookup

    func project(id: Project.ID) -> Project? {
        projects.first { $0.id == id }
    }

    func directory(for projectID: Project.ID) -> URL {
        projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    func fileURL(_ fileName: String, in projectID: Project.ID) -> URL {
        directory(for: projectID).appendingPathComponent(fileName)
    }

    // MARK: - Projects

    @discardableResult
    func createProject(name: String, subtitle: String = "") -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(
            name: trimmed.isEmpty ? "Untitled Project" : trimmed,
            subtitle: subtitle,
            floors: [Floor(name: Self.defaultFloorName)]
        )
        try? fileManager.createDirectory(at: directory(for: project.id), withIntermediateDirectories: true)
        projects.insert(project, at: 0)
        save()
        return project
    }

    func updateProject(_ projectID: Project.ID, name: String, subtitle: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(projectID) {
            if !trimmed.isEmpty { $0.name = trimmed }
            $0.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func deleteProject(_ projectID: Project.ID) {
        try? fileManager.removeItem(at: directory(for: projectID))
        projects.removeAll { $0.id == projectID }
        save()
    }

    // MARK: - Floors

    @discardableResult
    func addFloor(named name: String, to projectID: Project.ID) -> Floor? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let floor = Floor(name: trimmed.isEmpty ? "New Floor" : trimmed)
        var added = false
        mutate(projectID) { $0.floors.append(floor); added = true }
        return added ? floor : nil
    }

    func renameFloor(_ floorID: Floor.ID, in projectID: Project.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(projectID) { project in
            guard let i = project.floors.firstIndex(where: { $0.id == floorID }) else { return }
            project.floors[i].name = trimmed
        }
    }

    func moveFloor(_ floorID: Floor.ID, in projectID: Project.ID, by offset: Int) {
        mutate(projectID) { project in
            guard let i = project.floors.firstIndex(where: { $0.id == floorID }) else { return }
            let j = i + offset
            guard project.floors.indices.contains(j) else { return }
            project.floors.swapAt(i, j)
        }
    }

    /// Deletes a floor together with its plan and panoramas.
    func deleteFloor(_ floorID: Floor.ID, in projectID: Project.ID) {
        guard let project = self.project(id: projectID), let floor = project.floor(floorID) else { return }
        if let plan = floor.planFileName { removeFile(plan, in: projectID) }
        let removed = Set(project.panoramas(on: floorID).map(\.id))
        for panorama in project.panoramas(on: floorID) {
            removeFile(panorama.imageFileName, in: projectID)
            removeFile(panorama.thumbnailFileName, in: projectID)
        }
        mutate(projectID) { project in
            project.floors.removeAll { $0.id == floorID }
            project.panoramas.removeAll { removed.contains($0.id) }
            for i in project.panoramas.indices {
                project.panoramas[i].links.removeAll { removed.contains($0.targetID) }
            }
        }
    }

    /// Sets the plan drawing of a floor. Accepts an image or a PDF (first page is used).
    func setPlan(data: Data, for floorID: Floor.ID, in projectID: Project.ID) throws {
        let imageData: Data
        if ImageProcessing.isPDF(data) {
            guard let rendered = ImageProcessing.renderFirstPDFPage(data) else { throw ProjectStoreError.unsupportedFile }
            imageData = rendered
        } else if ImageProcessing.isImage(data) {
            imageData = data
        } else {
            throw ProjectStoreError.unsupportedFile
        }
        guard let floor = project(id: projectID)?.floor(floorID) else { throw ProjectStoreError.notFound }
        let name = try writeFile(imageData, prefix: "plan", in: projectID)
        if let old = floor.planFileName { removeFile(old, in: projectID) }
        mutate(projectID) { project in
            guard let i = project.floors.firstIndex(where: { $0.id == floorID }) else { return }
            project.floors[i].planFileName = name
        }
    }

    // MARK: - Panoramas

    @discardableResult
    func addPanorama(imageData: Data, title: String, floorID: Floor.ID, to projectID: Project.ID) throws -> Panorama {
        guard ImageProcessing.isImage(imageData) else { throw ProjectStoreError.unsupportedFile }
        guard let project = self.project(id: projectID), project.floor(floorID) != nil else { throw ProjectStoreError.notFound }

        let imageName = try writeFile(imageData, prefix: "pano", in: projectID)
        let thumbName = try writeThumbnail(for: imageName, in: projectID)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let panorama = Panorama(
            title: trimmed.isEmpty ? "Room \(project.panoramas(on: floorID).count + 1)" : trimmed,
            imageFileName: imageName,
            thumbnailFileName: thumbName,
            floorID: floorID
        )
        mutate(projectID) { $0.panoramas.append(panorama) }
        return panorama
    }

    func renamePanorama(_ panoramaID: Panorama.ID, in projectID: Project.ID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutatePanorama(panoramaID, in: projectID) { $0.title = trimmed }
    }

    func deletePanorama(_ panoramaID: Panorama.ID, from projectID: Project.ID) {
        guard let panorama = project(id: projectID)?.panorama(panoramaID) else { return }
        removeFile(panorama.imageFileName, in: projectID)
        removeFile(panorama.thumbnailFileName, in: projectID)
        mutate(projectID) { project in
            project.panoramas.removeAll { $0.id == panoramaID }
            for i in project.panoramas.indices {
                project.panoramas[i].links.removeAll { $0.targetID == panoramaID }
            }
        }
    }

    /// Places a panorama on its floor plan, or removes it from the plan when `position` is nil.
    func setPosition(_ position: LayoutPoint?, for panoramaID: Panorama.ID, in projectID: Project.ID) {
        mutatePanorama(panoramaID, in: projectID) {
            $0.layoutPosition = position.map { LayoutPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
        }
    }

    // MARK: - Links between panoramas

    func addLink(from sourceID: Panorama.ID, to targetID: Panorama.ID, yaw: Double, pitch: Double, in projectID: Project.ID) {
        guard sourceID != targetID else { return }
        mutatePanorama(sourceID, in: projectID) {
            $0.links.append(PanoramaLink(targetID: targetID, yaw: yaw, pitch: pitch))
        }
    }

    func removeLink(_ linkID: PanoramaLink.ID, from sourceID: Panorama.ID, in projectID: Project.ID) {
        mutatePanorama(sourceID, in: projectID) { $0.links.removeAll { $0.id == linkID } }
    }

    // MARK: - Drawings & renders

    @discardableResult
    func addDocument(data: Data, title: String, kind: ProjectDocument.Kind, to projectID: Project.ID) throws -> ProjectDocument {
        guard ImageProcessing.isPDF(data) || ImageProcessing.isImage(data) else { throw ProjectStoreError.unsupportedFile }
        guard let project = self.project(id: projectID) else { throw ProjectStoreError.notFound }
        let fileName = try writeFile(data, prefix: kind.rawValue, in: projectID)
        let thumbName = try writeThumbnail(for: fileName, in: projectID)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = ProjectDocument(
            title: trimmed.isEmpty ? "\(kind.singular) \(project.documents(of: kind).count + 1)" : trimmed,
            kind: kind,
            fileName: fileName,
            thumbnailFileName: thumbName
        )
        mutate(projectID) { $0.documents.append(document) }
        return document
    }

    func renameDocument(_ documentID: ProjectDocument.ID, in projectID: Project.ID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(projectID) { project in
            guard let i = project.documents.firstIndex(where: { $0.id == documentID }) else { return }
            project.documents[i].title = trimmed
        }
    }

    func deleteDocument(_ documentID: ProjectDocument.ID, from projectID: Project.ID) {
        guard let document = project(id: projectID)?.documents.first(where: { $0.id == documentID }) else { return }
        removeFile(document.fileName, in: projectID)
        removeFile(document.thumbnailFileName, in: projectID)
        mutate(projectID) { $0.documents.removeAll { $0.id == documentID } }
    }

    // MARK: - Sharing

    /// Writes the whole project into one `.visx` file in the temporary directory,
    /// ready to send via AirDrop, Messages, Mail, Files, etc.
    func exportArchive(for projectID: Project.ID) throws -> URL {
        guard let project = self.project(id: projectID) else { throw ProjectStoreError.notFound }
        var fileNames: [String] = project.panoramas.flatMap { [$0.imageFileName, $0.thumbnailFileName] }
        fileNames += project.floors.compactMap(\.planFileName)
        fileNames += project.documents.flatMap { [$0.fileName, $0.thumbnailFileName] }

        var files: [String: Data] = [:]
        for name in fileNames {
            files[name] = try? Data(contentsOf: fileURL(name, in: projectID))
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(ProjectArchive(project: project, files: files))

        let exportDir = fileManager.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? fileManager.removeItem(at: exportDir)
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let url = exportDir.appendingPathComponent("\(sanitizedFileName(project.name)).visx")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Imports a `.visx` file received from another device as a new project.
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

        var project = archive.project
        project.id = UUID() // Always import as a separate copy.
        project.name = uniqueName(for: project.name)
        let folder = directory(for: project.id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, fileData) in archive.files where !name.contains("/") {
            try fileData.write(to: folder.appendingPathComponent(name), options: .atomic)
        }
        projects.insert(project, at: 0)
        save()
        return project
    }

    // MARK: - Helpers

    private func mutate(_ projectID: Project.ID, _ change: (inout Project) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        change(&projects[index])
        save()
    }

    private func mutatePanorama(_ panoramaID: Panorama.ID, in projectID: Project.ID, _ change: (inout Panorama) -> Void) {
        mutate(projectID) { project in
            guard let i = project.panoramas.firstIndex(where: { $0.id == panoramaID }) else { return }
            change(&project.panoramas[i])
        }
    }

    private func writeFile(_ data: Data, prefix: String, in projectID: Project.ID) throws -> String {
        let folder = directory(for: projectID)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(prefix)-\(UUID().uuidString).\(ImageProcessing.fileExtension(for: data))"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        return name
    }

    private func writeThumbnail(for fileName: String, in projectID: Project.ID) throws -> String {
        let thumbName = "thumb-\(UUID().uuidString).jpg"
        if let thumb = ImageProcessing.thumbnailData(for: fileURL(fileName, in: projectID)) {
            try thumb.write(to: fileURL(thumbName, in: projectID), options: .atomic)
        }
        return thumbName
    }

    private func removeFile(_ name: String, in projectID: Project.ID) {
        try? fileManager.removeItem(at: fileURL(name, in: projectID))
    }

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
