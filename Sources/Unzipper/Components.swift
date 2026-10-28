import AppKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct BreadcrumbBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 5) {
            Button {
                model.goUp()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(model.currentPath.isEmpty || !model.searchText.isEmpty)
            .help("Enclosing folder (⌘↑)")

            if model.searchText.isEmpty {
                ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        model.navigate(to: crumb.path)
                    } label: {
                        Text(crumb.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .fontWeight(index == model.breadcrumb.count - 1 ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == model.breadcrumb.count - 1 ? .primary : .secondary)
                }
            } else {
                Label("Search results", systemImage: "magnifyingglass")
                    .font(.callout.weight(.medium))
                Text("for “\(model.searchText)”")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Clear") { model.searchText = "" }
                    .buttonStyle(.link)
                    .font(.callout)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct StatusBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Text(model.selectionText)
            Spacer()
            Text(model.footerText)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.bar)
    }
}

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.accentColor,
                              style: StrokeStyle(lineWidth: 2.5, dash: [9, 6]))
                .padding(26)
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.accentColor)
                Text("Drop to open")
                    .font(.title2.weight(.semibold))
                Text("Archives open instantly. Files and folders create a new archive.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

struct BusyOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(.separator))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
    }
}

struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)
        view?.autostarts = true
        view?.previewItem = url as NSURL
        return view ?? QLPreviewView(frame: .zero)
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL
        nsView.refreshPreviewItem()
    }
}

enum DropHandler {
    static func urls(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var result: [URL] = []

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                } else if let string = item as? String {
                    url = URL(fileURLWithPath: string)
                }
                if let url {
                    lock.lock()
                    result.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            completion(result)
        }
    }
}
