import AppKit
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer(minLength: 28)
                icon
                dropCard
                    .padding(.top, 22)
                if !model.recents.isEmpty {
                    recents
                        .padding(.top, 22)
                }
                Spacer(minLength: 20)
                Text("ZIP · RAR · 7Z · TAR · GZIP · BZIP2 · XZ · CAB · ISO")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 660)
        }
    }

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.accentColor.opacity(0.10), .clear],
                           center: .top, startRadius: 20, endRadius: 520)
            LinearGradient(colors: [.clear, Color.accentColor.opacity(0.035)],
                           startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var icon: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            VStack(spacing: 6) {
                Text("Unzipper")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Fast, native archive extraction for macOS")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dropCard: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 68, height: 68)
                Image(systemName: "archivebox")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 5) {
                Text("Drop an archive here")
                    .font(.title3.weight(.semibold))
                Text("or open one from Finder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button {
                    model.chooseArchive()
                } label: {
                    Label("Open Archive…", systemImage: "folder")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button {
                    model.presentNewArchive()
                } label: {
                    Label("New Archive…", systemImage: "doc.badge.plus")
                        .frame(minWidth: 120)
                }
                .controlSize(.large)
            }
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color(nsColor: .separatorColor),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        )
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.headline)
                .padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(model.recents.prefix(5).enumerated()), id: \.element) { index, url in
                    recentRow(url)
                    if index < min(model.recents.count, 5) - 1 {
                        Divider().padding(.leading, 42)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6))
            )
        }
    }

    private func recentRow(_ url: URL) -> some View {
        Button {
            model.open(url)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: FileIcons.icon(name: url.lastPathComponent, isDirectory: false))
                    .resizable()
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { model.open(url) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Divider()
            Button("Remove from Recents") { model.removeRecent(url) }
        }
    }
}
