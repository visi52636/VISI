import SwiftUI

/// Where an import should go. Drives the single photo picker / file importer of a project screen.
enum ImportTarget: Equatable {
    case panoramas(Floor.ID)
    case plan(Floor.ID)
    case documents(ProjectDocument.Kind)
}

enum ImportSource {
    case photos, files
}

/// Centered placeholder with an icon, a short explanation and optional actions.
struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            actions()
                .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

/// "Photos" + "Files" pair of buttons used in empty states.
struct ImportButtons: View {
    let onSelect: (ImportSource) -> Void
    var filesLabel = "Files"

    var body: some View {
        HStack(spacing: 12) {
            Button { onSelect(.photos) } label: { Label("Photos", systemImage: "photo") }
            Button { onSelect(.files) } label: { Label(filesLabel, systemImage: "folder") }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

/// Menu offering Photos or Files as the source of an import.
struct ImportMenu<Label: View>: View {
    let onSelect: (ImportSource) -> Void
    var filesTitle = "Choose from Files"
    @ViewBuilder var label: () -> Label

    var body: some View {
        Menu {
            Button { onSelect(.photos) } label: { SwiftUI.Label("Photo Library", systemImage: "photo") }
            Button { onSelect(.files) } label: { SwiftUI.Label(filesTitle, systemImage: "folder") }
        } label: {
            label()
        }
    }
}

/// Pill-shaped selectable chip (floors, filters).
struct Chip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
            .background(isSelected ? Color.primary : Color(.secondarySystemFill), in: Capsule())
    }
}

/// Minimal text tabs with an underline for the selected item.
struct UnderlineTabs<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    @Namespace private var underline

    var body: some View {
        HStack(spacing: 24) {
            ForEach(items, id: \.self) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = item }
                } label: {
                    VStack(spacing: 6) {
                        Text(title(item))
                            .font(.subheadline.weight(selection == item ? .semibold : .regular))
                            .foregroundStyle(selection == item ? Color.primary : Color.secondary)
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 2)
                            if selection == item {
                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

/// Square-cornered image tile with a caption, used for rooms, drawings and renders.
struct ImageTile: View {
    let url: URL?
    let title: String
    var aspectRatio: CGFloat = 1.5
    var fit = false
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(url: url, contentMode: fit ? .fit : .fill)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2.5)
                )
            Text(title)
                .font(.footnote)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }
}

/// Dashed "add" tile shown in edit mode.
struct AddTile: View {
    let title: String
    var aspectRatio: CGFloat = 1.5

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.secondary)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay(Image(systemName: "plus").font(.title3).foregroundStyle(.secondary))
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// Simple error alert bound to an optional message.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("Something went wrong", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
