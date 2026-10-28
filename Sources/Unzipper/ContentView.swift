import AppKit
import SwiftUI

struct PreviewSheet: View {
    let item: PreviewItem

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: FileIcons.icon(name: item.title, isDirectory: false))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(item.url)
                } label: {
                    Label("Open With", systemImage: "arrow.up.forward.app")
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            QuickLookView(url: item.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 900, height: 620)
        .onDisappear {
            model.cleanupPreview()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            if model.archiveURL == nil {
                WelcomeView()
            } else {
                BrowserView()
            }

            if model.isLoading {
                loadingOverlay
            }

            if let busy = model.busyMessage {
                BusyOverlay(message: busy)
                    .transition(.opacity)
            }

            if model.isDropTargeted {
                DropOverlay()
            }
        }
        .frame(minWidth: 900, minHeight: 540)
        .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted) { providers in
            DropHandler.urls(from: providers) { urls in
                model.handleDrop(urls)
            }
            return true
        }
        .toolbar { toolbar }
        .navigationTitle(model.windowTitle)
        .navigationSubtitle(model.windowSubtitle)
        .sheet(item: $model.extractContext) { context in
            ExtractSheet(context: context)
                .environmentObject(model)
        }
        .sheet(item: $model.createContext) { context in
            CreateArchiveSheet(context: context)
                .environmentObject(model)
        }
        .sheet(item: $model.previewItem, onDismiss: { model.cleanupPreview() }) { item in
            PreviewSheet(item: item)
                .environmentObject(model)
        }
        .alert("Unzipper", isPresented: alertBinding) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(text: toast)
                    .padding(.bottom, 34)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: model.toast)
        .animation(.easeInOut(duration: 0.15), value: model.isDropTargeted)
        .animation(.easeInOut(duration: 0.15), value: model.busyMessage)
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { model.alertMessage != nil },
                set: { newValue in if !newValue { model.alertMessage = nil } })
    }

    private var loadingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Reading \(model.archiveURL?.lastPathComponent ?? "archive")…")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.chooseArchive()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open Archive (⌘O)")

            Button {
                model.presentNewArchive()
            } label: {
                Label("New", systemImage: "doc.badge.plus")
            }
            .help("New Archive (⌘N)")
        }

        if model.archiveURL != nil {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Extract All…") { model.extractAll() }
                    Button("Extract Selected…") { model.extractSelected() }
                        .disabled(model.selection.isEmpty)
                    Divider()
                    Button("Reveal Archive in Finder") { model.revealArchive() }
                } label: {
                    Label("Extract", systemImage: "arrow.down.doc")
                } primaryAction: {
                    model.extractAll()
                }
                .disabled(model.listing == nil)
                .help("Extract (⌘E)")

                Button {
                    model.quickLookSelection()
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                .disabled(!canPreviewSelection)
                .help("Quick Look (⌘Y)")
            }
        }
    }

    private var canPreviewSelection: Bool {
        model.rows.contains { row in
            model.selection.contains(row.id) && !row.isDirectory
        }
    }
}
