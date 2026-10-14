import UIKit

/// Launch options used for demos and automated screenshots, e.g. `-VISXDemo YES -VISXScreen viewer`.
enum LaunchOptions {
    static var isDemo: Bool { UserDefaults.standard.bool(forKey: "VISXDemo") }
    static var screen: String? { UserDefaults.standard.string(forKey: "VISXScreen") }
}

/// Generates a sample architecture project with synthetic plans, 360° views, drawings and renders.
/// Only used when the app is launched with `-VISXDemo YES`.
@MainActor
enum DemoContent {
    private struct Room {
        let name: String
        let rect: CGRect // normalized
        var pin: Bool = true
    }

    private static let groundRooms = [
        Room(name: "Living Room", rect: CGRect(x: 0.27, y: 0.06, width: 0.42, height: 0.52)),
        Room(name: "Kitchen", rect: CGRect(x: 0.69, y: 0.06, width: 0.25, height: 0.44)),
        Room(name: "Dining", rect: CGRect(x: 0.69, y: 0.50, width: 0.25, height: 0.44)),
        Room(name: "Entrance", rect: CGRect(x: 0.06, y: 0.58, width: 0.21, height: 0.36)),
        Room(name: "WC", rect: CGRect(x: 0.06, y: 0.06, width: 0.21, height: 0.26), pin: false),
        Room(name: "Hall", rect: CGRect(x: 0.27, y: 0.58, width: 0.42, height: 0.36), pin: false),
        Room(name: "Stairs", rect: CGRect(x: 0.06, y: 0.32, width: 0.21, height: 0.26), pin: false)
    ]

    private static let firstRooms = [
        Room(name: "Master Bedroom", rect: CGRect(x: 0.27, y: 0.06, width: 0.42, height: 0.52)),
        Room(name: "Bedroom 2", rect: CGRect(x: 0.69, y: 0.06, width: 0.25, height: 0.44)),
        Room(name: "Study", rect: CGRect(x: 0.69, y: 0.50, width: 0.25, height: 0.44)),
        Room(name: "Bathroom", rect: CGRect(x: 0.06, y: 0.58, width: 0.21, height: 0.36)),
        Room(name: "Landing", rect: CGRect(x: 0.27, y: 0.58, width: 0.42, height: 0.36), pin: false),
        Room(name: "Stairs", rect: CGRect(x: 0.06, y: 0.32, width: 0.21, height: 0.26), pin: false),
        Room(name: "Storage", rect: CGRect(x: 0.06, y: 0.06, width: 0.21, height: 0.26), pin: false)
    ]

    static func install(in store: ProjectStore) {
        for project in store.projects { store.deleteProject(project.id) }

        // Second, smaller project so the home screen shows more than one card.
        let office = store.createProject(name: "Harbour Office Fit-out", subtitle: "Level 4 · Client: Meridian")
        try? store.addDocument(data: render(seed: 3), title: "Reception", kind: .render, to: office.id)

        let villa = store.createProject(name: "Lakeside Villa", subtitle: "Private residence · Como")
        guard let ground = store.project(id: villa.id)?.floors.first else { return }
        let first = store.addFloor(named: "First Floor", to: villa.id)
        let site = store.addFloor(named: "Site / Exterior", to: villa.id)

        try? store.setPlan(data: planPNG(rooms: groundRooms, title: "GROUND FLOOR"), for: ground.id, in: villa.id)
        if let first {
            try? store.setPlan(data: planPNG(rooms: firstRooms, title: "FIRST FLOOR"), for: first.id, in: villa.id)
        }
        if let site {
            try? store.setPlan(data: sitePlanPNG(), for: site.id, in: villa.id)
        }

        let palette: [(wall: UIColor, floor: UIColor)] = [
            (UIColor(white: 0.93, alpha: 1), UIColor(red: 0.62, green: 0.47, blue: 0.33, alpha: 1)),
            (UIColor(red: 0.90, green: 0.91, blue: 0.89, alpha: 1), UIColor(white: 0.75, alpha: 1)),
            (UIColor(red: 0.94, green: 0.91, blue: 0.86, alpha: 1), UIColor(red: 0.55, green: 0.40, blue: 0.28, alpha: 1)),
            (UIColor(red: 0.86, green: 0.89, blue: 0.91, alpha: 1), UIColor(white: 0.55, alpha: 1))
        ]

        var created: [String: Panorama] = [:]
        func addRooms(_ rooms: [Room], floorID: Floor.ID) {
            for (index, room) in rooms.enumerated() where room.pin {
                let colors = palette[index % palette.count]
                guard let pano = try? store.addPanorama(
                    imageData: interiorPanorama(wall: colors.wall, floor: colors.floor, seed: index),
                    title: room.name, floorID: floorID, to: villa.id
                ) else { continue }
                store.setPosition(LayoutPoint(x: room.rect.midX, y: room.rect.midY), for: pano.id, in: villa.id)
                created[room.name] = pano
            }
        }
        addRooms(groundRooms, floorID: ground.id)
        if let first { addRooms(firstRooms, floorID: first.id) }
        if let site, let garden = try? store.addPanorama(imageData: exteriorPanorama(), title: "Garden", floorID: site.id, to: villa.id) {
            store.setPosition(LayoutPoint(x: 0.5, y: 0.78), for: garden.id, in: villa.id)
            created["Garden"] = garden
        }

        // Doorways between rooms, all roughly ahead of the starting view.
        let links: [(String, String, Double, Double)] = [
            ("Living Room", "Kitchen", 0.35, -0.08), ("Living Room", "Entrance", -0.55, -0.1),
            ("Living Room", "Garden", 0.0, -0.02),
            ("Kitchen", "Dining", 0.2, -0.1), ("Kitchen", "Living Room", -0.3, -0.1),
            ("Dining", "Kitchen", 0.2, -0.1), ("Entrance", "Living Room", 0.1, -0.1),
            ("Entrance", "Master Bedroom", -0.5, 0.05),
            ("Master Bedroom", "Bathroom", 0.3, -0.1), ("Master Bedroom", "Entrance", -0.4, -0.1),
            ("Bedroom 2", "Study", 0.2, -0.1), ("Study", "Bedroom 2", -0.2, -0.1),
            ("Bathroom", "Master Bedroom", 0.1, -0.1), ("Garden", "Living Room", 0.0, -0.05)
        ]
        for (from, to, yaw, pitch) in links {
            if let a = created[from], let b = created[to] {
                store.addLink(from: a.id, to: b.id, yaw: yaw, pitch: pitch, in: villa.id)
            }
        }

        for (index, title) in ["Lake View", "Living Room", "Evening Terrace", "Entrance Court"].enumerated() {
            try? store.addDocument(data: render(seed: index), title: title, kind: .render, to: villa.id)
        }
        try? store.addDocument(data: drawingPDF(rooms: groundRooms, title: "GROUND FLOOR PLAN", number: "A-101"),
                               title: "A-101 Ground Floor Plan", kind: .drawing, to: villa.id)
        try? store.addDocument(data: drawingPDF(rooms: firstRooms, title: "FIRST FLOOR PLAN", number: "A-102"),
                               title: "A-102 First Floor Plan", kind: .drawing, to: villa.id)
        try? store.addDocument(data: planPNG(rooms: groundRooms, title: "FURNITURE LAYOUT"),
                               title: "A-110 Furniture Layout", kind: .drawing, to: villa.id)
    }

    // MARK: - Plans

    private static func drawPlan(rooms: [Room], title: String, in rect: CGRect, context cg: CGContext) {
        let wall = UIColor(white: 0.12, alpha: 1)
        cg.setStrokeColor(wall.cgColor)
        for room in rooms {
            let r = CGRect(x: rect.minX + room.rect.minX * rect.width, y: rect.minY + room.rect.minY * rect.height,
                           width: room.rect.width * rect.width, height: room.rect.height * rect.height)
            cg.setLineWidth(rect.width * 0.006)
            cg.stroke(r)
            let font = UIFont.systemFont(ofSize: rect.width * 0.017, weight: .medium)
            let label = room.name.uppercased() as NSString
            let size = label.size(withAttributes: [.font: font])
            label.draw(at: CGPoint(x: r.midX - size.width / 2, y: r.midY + rect.height * 0.04),
                       withAttributes: [.font: font, .foregroundColor: UIColor(white: 0.45, alpha: 1), .kern: 1.5])
            // Door openings.
            UIColor.white.setFill()
            cg.fill(CGRect(x: r.midX - rect.width * 0.03, y: r.maxY - rect.width * 0.005,
                           width: rect.width * 0.06, height: rect.width * 0.01))
        }
        // Outer wall.
        cg.setLineWidth(rect.width * 0.012)
        cg.stroke(CGRect(x: rect.minX + 0.06 * rect.width, y: rect.minY + 0.06 * rect.height,
                         width: 0.88 * rect.width, height: 0.88 * rect.height))
        // Stair treads.
        if let stairs = rooms.first(where: { $0.name == "Stairs" }) {
            cg.setLineWidth(rect.width * 0.0015)
            for i in 1..<8 {
                let x = rect.minX + (stairs.rect.minX + stairs.rect.width * CGFloat(i) / 8) * rect.width
                cg.move(to: CGPoint(x: x, y: rect.minY + stairs.rect.minY * rect.height))
                cg.addLine(to: CGPoint(x: x, y: rect.minY + stairs.rect.maxY * rect.height))
            }
            cg.strokePath()
        }
        let titleFont = UIFont.systemFont(ofSize: rect.width * 0.02, weight: .semibold)
        (title as NSString).draw(at: CGPoint(x: rect.minX + 0.06 * rect.width, y: rect.minY + 0.955 * rect.height),
                                 withAttributes: [.font: titleFont, .foregroundColor: wall, .kern: 3])
    }

    private static func planPNG(rooms: [Room], title: String) -> Data {
        let size = CGSize(width: 2000, height: 1400)
        return image(size: size) { cg in
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            drawPlan(rooms: rooms, title: title, in: CGRect(origin: .zero, size: size), context: cg)
        }.pngData() ?? Data()
    }

    private static func sitePlanPNG() -> Data {
        let size = CGSize(width: 2000, height: 1400)
        return image(size: size) { cg in
            UIColor(red: 0.93, green: 0.95, blue: 0.91, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.80, green: 0.88, blue: 0.95, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size.width, height: 260)) // lake
            UIColor(white: 0.12, alpha: 1).setStroke()
            cg.setLineWidth(10)
            cg.stroke(CGRect(x: 650, y: 420, width: 700, height: 480)) // house
            UIColor(red: 0.62, green: 0.74, blue: 0.56, alpha: 1).setFill()
            for (x, y) in [(300, 500), (420, 900), (1600, 560), (1700, 1000), (280, 1150)] {
                cg.fillEllipse(in: CGRect(x: x, y: y, width: 150, height: 150))
            }
            UIColor(white: 0.82, alpha: 1).setFill()
            cg.fill(CGRect(x: 940, y: 900, width: 120, height: 500)) // path
            let font = UIFont.systemFont(ofSize: 40, weight: .semibold)
            ("SITE PLAN" as NSString).draw(at: CGPoint(x: 120, y: 1320),
                                           withAttributes: [.font: font, .foregroundColor: UIColor(white: 0.12, alpha: 1), .kern: 3])
            ("LAKE COMO" as NSString).draw(at: CGPoint(x: 880, y: 110),
                                           withAttributes: [.font: font, .foregroundColor: UIColor(red: 0.3, green: 0.45, blue: 0.6, alpha: 1), .kern: 6])
        }.pngData() ?? Data()
    }

    private static func drawingPDF(rooms: [Room], title: String, number: String) -> Data {
        let page = CGRect(x: 0, y: 0, width: 1191, height: 842) // A3 landscape, points
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(2)
            cg.stroke(page.insetBy(dx: 20, dy: 20))
            drawPlan(rooms: rooms, title: "", in: CGRect(x: 40, y: 40, width: 860, height: 700), context: cg)
            let block = CGRect(x: 930, y: 640, width: 241, height: 182)
            cg.stroke(block)
            let small = UIFont.systemFont(ofSize: 10)
            let big = UIFont.systemFont(ofSize: 18, weight: .semibold)
            ("LAKESIDE VILLA" as NSString).draw(at: CGPoint(x: 942, y: 652), withAttributes: [.font: small])
            (title as NSString).draw(at: CGPoint(x: 942, y: 680), withAttributes: [.font: big])
            ("SCALE 1:100 @ A3" as NSString).draw(at: CGPoint(x: 942, y: 760), withAttributes: [.font: small])
            (number as NSString).draw(at: CGPoint(x: 942, y: 785), withAttributes: [.font: big])
        }
    }

    // MARK: - Panoramas (equirectangular, 2:1)

    private static func interiorPanorama(wall: UIColor, floor: UIColor, seed: Int) -> Data {
        let size = CGSize(width: 4096, height: 2048)
        let w = size.width, h = size.height
        return image(size: size) { cg in
            // Ceiling, walls, floor.
            UIColor(white: 0.97, alpha: 1).setFill(); cg.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.32))
            wall.setFill(); cg.fill(CGRect(x: 0, y: h * 0.32, width: w, height: h * 0.32))
            floor.setFill(); cg.fill(CGRect(x: 0, y: h * 0.64, width: w, height: h * 0.36))
            UIColor.black.withAlphaComponent(0.06).setFill()
            for i in 0..<40 { cg.fill(CGRect(x: 0, y: h * 0.64 + CGFloat(i) * h * 0.009, width: w, height: 2)) }

            // Shade alternate walls and draw corners.
            for k in 0..<4 {
                let x0 = w * (0.125 + 0.25 * CGFloat(k))
                if k % 2 == 0 {
                    UIColor.black.withAlphaComponent(0.04).setFill()
                    cg.fill(CGRect(x: x0, y: h * 0.32, width: w * 0.25, height: h * 0.32))
                }
                UIColor.black.withAlphaComponent(0.18).setFill()
                cg.fill(CGRect(x: x0 - 2, y: h * 0.32, width: 4, height: h * 0.32))
            }
            // Ceiling & skirting lines.
            UIColor.black.withAlphaComponent(0.12).setFill()
            cg.fill(CGRect(x: 0, y: h * 0.32 - 2, width: w, height: 4))
            UIColor.white.setFill()
            cg.fill(CGRect(x: 0, y: h * 0.63, width: w, height: h * 0.012))

            // Large windows with sky and lake.
            for (i, cx) in [0.5, 0.82].enumerated() where (seed + i) % 3 != 2 {
                let rect = CGRect(x: w * CGFloat(cx) - w * 0.07, y: h * 0.36, width: w * 0.14, height: h * 0.24)
                let colors = [UIColor(red: 0.62, green: 0.80, blue: 0.95, alpha: 1).cgColor,
                              UIColor(red: 0.86, green: 0.93, blue: 0.98, alpha: 1).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    cg.saveGState(); cg.clip(to: rect)
                    cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
                    cg.restoreGState()
                }
                UIColor(red: 0.45, green: 0.62, blue: 0.72, alpha: 1).setFill()
                cg.fill(CGRect(x: rect.minX, y: rect.maxY - rect.height * 0.25, width: rect.width, height: rect.height * 0.25))
                UIColor(white: 0.2, alpha: 1).setStroke(); cg.setLineWidth(10); cg.stroke(rect)
                cg.setLineWidth(6)
                cg.move(to: CGPoint(x: rect.midX, y: rect.minY)); cg.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)); cg.strokePath()
            }
            // Doors.
            for cx in [0.18, 0.62] {
                let rect = CGRect(x: w * CGFloat(cx) - w * 0.025, y: h * 0.40, width: w * 0.05, height: h * 0.24)
                UIColor(red: 0.42, green: 0.33, blue: 0.26, alpha: 1).setFill(); cg.fill(rect)
                UIColor.white.setStroke(); cg.setLineWidth(8); cg.stroke(rect)
            }
            // Furniture: low sofa / counter and a rug.
            UIColor(white: 0.3, alpha: 1).setFill()
            cg.fill(CGRect(x: w * 0.42, y: h * 0.56, width: w * 0.16, height: h * 0.08))
            UIColor(white: 0.96, alpha: 0.6).setFill()
            cg.fillEllipse(in: CGRect(x: w * 0.38, y: h * 0.72, width: w * 0.24, height: h * 0.14))
            // Pendant lights.
            UIColor(white: 0.15, alpha: 1).setFill()
            for cx in [0.47, 0.53] {
                cg.fill(CGRect(x: w * CGFloat(cx), y: h * 0.18, width: 3, height: h * 0.12))
                cg.fillEllipse(in: CGRect(x: w * CGFloat(cx) - 20, y: h * 0.29, width: 43, height: 30))
            }
        }.jpegData(compressionQuality: 0.85) ?? Data()
    }

    private static func exteriorPanorama() -> Data {
        let size = CGSize(width: 4096, height: 2048)
        let w = size.width, h = size.height
        return image(size: size) { cg in
            let sky = [UIColor(red: 0.42, green: 0.65, blue: 0.92, alpha: 1).cgColor,
                       UIColor(red: 0.85, green: 0.92, blue: 0.98, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h * 0.5), options: [])
            }
            UIColor(red: 0.45, green: 0.62, blue: 0.40, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: h * 0.5, width: w, height: h * 0.5))
            UIColor(red: 0.55, green: 0.66, blue: 0.75, alpha: 1).setFill()
            for i in 0..<6 {
                let x = w * CGFloat(i) / 6
                cg.move(to: CGPoint(x: x, y: h * 0.5))
                cg.addLine(to: CGPoint(x: x + w * 0.09, y: h * 0.42))
                cg.addLine(to: CGPoint(x: x + w * 0.2, y: h * 0.5))
                cg.fillPath()
            }
            // House facade straight ahead.
            UIColor(white: 0.96, alpha: 1).setFill()
            cg.fill(CGRect(x: w * 0.40, y: h * 0.34, width: w * 0.20, height: h * 0.17))
            UIColor(white: 0.25, alpha: 1).setFill()
            cg.fill(CGRect(x: w * 0.39, y: h * 0.33, width: w * 0.22, height: h * 0.012))
            UIColor(red: 0.30, green: 0.40, blue: 0.48, alpha: 1).setFill()
            for i in 0..<4 {
                cg.fill(CGRect(x: w * (0.415 + 0.045 * CGFloat(i)), y: h * 0.37, width: w * 0.03, height: h * 0.11))
            }
            // Trees.
            UIColor(red: 0.28, green: 0.45, blue: 0.28, alpha: 1).setFill()
            for cx in [0.08, 0.27, 0.70, 0.88] {
                cg.fillEllipse(in: CGRect(x: w * CGFloat(cx), y: h * 0.33, width: w * 0.06, height: h * 0.15))
            }
            // Path.
            UIColor(white: 0.85, alpha: 1).setFill()
            cg.move(to: CGPoint(x: w * 0.47, y: h * 0.51)); cg.addLine(to: CGPoint(x: w * 0.53, y: h * 0.51))
            cg.addLine(to: CGPoint(x: w * 0.6, y: h)); cg.addLine(to: CGPoint(x: w * 0.4, y: h)); cg.fillPath()
        }.jpegData(compressionQuality: 0.85) ?? Data()
    }

    // MARK: - Renders

    private static func render(seed: Int) -> Data {
        let size = CGSize(width: 1800, height: 1200)
        let w = size.width, h = size.height
        let skies: [(UIColor, UIColor)] = [
            (UIColor(red: 0.45, green: 0.66, blue: 0.90, alpha: 1), UIColor(red: 0.90, green: 0.94, blue: 0.98, alpha: 1)),
            (UIColor(red: 0.80, green: 0.84, blue: 0.88, alpha: 1), UIColor(white: 0.97, alpha: 1)),
            (UIColor(red: 0.20, green: 0.22, blue: 0.40, alpha: 1), UIColor(red: 0.95, green: 0.62, blue: 0.40, alpha: 1)),
            (UIColor(red: 0.60, green: 0.75, blue: 0.88, alpha: 1), UIColor(red: 0.96, green: 0.95, blue: 0.90, alpha: 1))
        ]
        let sky = skies[seed % skies.count]
        return image(size: size) { cg in
            let colors = [sky.0.cgColor, sky.1.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h * 0.7), options: [])
            }
            let ground = seed == 0 ? UIColor(red: 0.42, green: 0.58, blue: 0.70, alpha: 1) : UIColor(red: 0.62, green: 0.64, blue: 0.56, alpha: 1)
            ground.setFill(); cg.fill(CGRect(x: 0, y: h * 0.7, width: w, height: h * 0.3))

            // Two cantilevered volumes.
            let lit = seed == 2
            let volumes = [CGRect(x: w * 0.18, y: h * 0.42, width: w * 0.5, height: h * 0.28),
                           CGRect(x: w * 0.38, y: h * 0.24, width: w * 0.46, height: h * 0.18)]
            for (i, v) in volumes.enumerated() {
                UIColor(white: i == 0 ? 0.92 : 0.98, alpha: 1).setFill(); cg.fill(v)
                UIColor.black.withAlphaComponent(0.12).setFill()
                cg.fill(CGRect(x: v.minX, y: v.maxY - 8, width: v.width, height: 8))
                let glass = lit ? UIColor(red: 1.0, green: 0.82, blue: 0.52, alpha: 1) : UIColor(red: 0.26, green: 0.36, blue: 0.44, alpha: 1)
                glass.setFill()
                cg.fill(v.insetBy(dx: v.width * 0.06, dy: v.height * 0.2))
                UIColor(white: 0.9, alpha: 1).setFill()
                let panes = 6
                for p in 1..<panes {
                    let inner = v.insetBy(dx: v.width * 0.06, dy: v.height * 0.2)
                    cg.fill(CGRect(x: inner.minX + inner.width * CGFloat(p) / CGFloat(panes) - 3, y: inner.minY, width: 6, height: inner.height))
                }
            }
            // Shadow and trees.
            UIColor.black.withAlphaComponent(0.15).setFill()
            cg.fillEllipse(in: CGRect(x: w * 0.15, y: h * 0.68, width: w * 0.62, height: h * 0.06))
            UIColor(red: 0.25, green: 0.38, blue: 0.27, alpha: 1).setFill()
            for cx in [0.06, 0.86, 0.93] {
                cg.fillEllipse(in: CGRect(x: w * CGFloat(cx), y: h * 0.40, width: w * 0.09, height: h * 0.32))
            }
        }.jpegData(compressionQuality: 0.88) ?? Data()
    }

    private static func image(size: CGSize, draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }
}
