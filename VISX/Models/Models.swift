import Foundation

/// A normalized point on a floor plan: (0,0) is top-left, (1,1) is bottom-right.
struct LayoutPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

/// A clickable "door" inside a panorama that jumps to another panorama.
/// `yaw`/`pitch` (radians) give the direction where the hotspot is shown.
struct PanoramaLink: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var targetID: Panorama.ID
    var yaw: Double
    var pitch: Double
}

/// A 360° equirectangular panorama of a room or exterior view.
struct Panorama: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var imageFileName: String
    var thumbnailFileName: String
    var createdAt: Date = Date()
    var floorID: Floor.ID
    /// Position on the floor plan; `nil` while not placed yet.
    var layoutPosition: LayoutPoint?
    var links: [PanoramaLink] = []
}

/// A level of the building (or the site / exterior) with an optional plan drawing.
struct Floor: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var planFileName: String?
}

/// A drawing or render the client can browse.
struct ProjectDocument: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case drawing, render
        var id: String { rawValue }
        var title: String { self == .drawing ? "Drawings" : "Renders" }
        var singular: String { self == .drawing ? "Drawing" : "Render" }
    }

    var id: UUID = UUID()
    var title: String
    var kind: Kind
    var fileName: String
    var thumbnailFileName: String
    var createdAt: Date = Date()
}

/// An architecture project: floors with plans, 360° panoramas, drawings and renders.
struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var subtitle: String = ""
    var createdAt: Date = Date()
    var floors: [Floor] = []
    var panoramas: [Panorama] = []
    var documents: [ProjectDocument] = []

    func panoramas(on floorID: Floor.ID) -> [Panorama] {
        panoramas.filter { $0.floorID == floorID }
    }

    func panorama(_ id: Panorama.ID) -> Panorama? {
        panoramas.first { $0.id == id }
    }

    func floor(_ id: Floor.ID) -> Floor? {
        floors.first { $0.id == id }
    }

    func documents(of kind: ProjectDocument.Kind) -> [ProjectDocument] {
        documents.filter { $0.kind == kind }
    }

    /// Image used on the project card: first render, otherwise first panorama.
    var coverFileName: String? {
        documents(of: .render).first?.thumbnailFileName ?? panoramas.first?.thumbnailFileName
    }
}

/// Portable single-file representation of a project (`.visx`), used to share with other devices.
/// Contains the project description plus every file it references.
struct ProjectArchive: Codable {
    static let formatVersion = 2

    var version: Int = ProjectArchive.formatVersion
    var project: Project
    var files: [String: Data]
}
