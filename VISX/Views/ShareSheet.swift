import SwiftUI
import UIKit

/// Wraps `UIActivityViewController` so files can be sent via AirDrop, Messages, Mail, Files, etc.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable wrapper so a share sheet can be driven by `.sheet(item:)`.
struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}
