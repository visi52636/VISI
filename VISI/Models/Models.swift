import Foundation

/// A single 360° equirectangular panorama stored inside a project.
struct Panorama: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var imageFileName: String
    var thumbnailFileName: String
    var createdAt: Date = Date()
}

/// A named collection of panoramas (e.g. a building site, a property, a trip).
struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var notes: String = ""
    var createdAt: Date = Date()
    var panoramas: [Panorama] = []
}

/// Portable representation of a project used for sharing between devices.
/// Written as a binary property list with the `.visiproj` extension.
struct ProjectArchive: Codable {
    struct Item: Codable {
        var title: String
        var createdAt: Date
        var imageData: Data
    }

    static let formatVersion = 1

    var version: Int = ProjectArchive.formatVersion
    var name: String
    var notes: String
    var createdAt: Date
    var items: [Item]
}
