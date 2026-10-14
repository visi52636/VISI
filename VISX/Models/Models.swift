import Foundation

/// A single 360° equirectangular panorama stored inside a project.
struct Panorama: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var imageFileName: String
    var thumbnailFileName: String
    var createdAt: Date = Date()
    /// Where the panorama was taken on the project layout, normalized to 0...1. `nil` = not placed.
    var layoutPosition: LayoutPoint?
}

/// A point on the layout image, normalized so (0,0) is top-left and (1,1) is bottom-right.
struct LayoutPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

/// A named collection of panoramas (e.g. a building site, a property, a trip).
struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var notes: String = ""
    var createdAt: Date = Date()
    var panoramas: [Panorama] = []
    /// Floor plan / site layout image file, stored in the project folder.
    var layoutImageFileName: String?
}

/// Portable representation of a project used for sharing between devices.
/// Written as a binary property list with the `.visx` extension.
struct ProjectArchive: Codable {
    struct Item: Codable {
        var title: String
        var createdAt: Date
        var imageData: Data
        var layoutPosition: LayoutPoint?
    }

    static let formatVersion = 1

    var version: Int = ProjectArchive.formatVersion
    var name: String
    var notes: String
    var createdAt: Date
    var items: [Item]
    var layoutImageData: Data?
}
