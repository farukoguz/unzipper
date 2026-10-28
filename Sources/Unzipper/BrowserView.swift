import AppKit
import SwiftUI

struct BrowserView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbBar()
            Divider()
            ZStack {
                archiveTable
                if model.rows.isEmpty && !model.isLoading {
                    emptyState
                }
            }
            Divider()
            StatusBar()
        }
    }

    private var archiveTable: some View {
        Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.sortName) { row in
                HStack(spacing: 7) {
                    Image(nsImage: FileIcons.icon(name: row.name, isDirectory: row.isDirectory))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(row.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if row.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .help("Encrypted")
                    }
                }
                .padding(.leading, 2)
            }
            .width(min: 240, ideal: 380)

            TableColumn("Size", value: \.sortSize) { row in
                Text(Formatting.compactSize(row.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 72, ideal: 84)

            TableColumn("Packed", value: \.sortPacked) { row in
                Text(row.isDirectory ? "—" : Formatting.compactSize(row.packedSize))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 72, ideal: 84)

            TableColumn("Ratio", value: \.sortRatio) { row in
                Text(row.isDirectory ? "—" : Formatting.ratio(row.size, row.packedSize))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 56, ideal: 64)

            TableColumn("Modified", value: \.sortModified) { row in
                Text(Formatting.tableDate(row.modified))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 128, ideal: 146)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .environment(\.defaultMinListRowHeight, 24)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search archive")
        .onKeyPress(.return) {
            guard !model.selection.isEmpty else { return .ignored }
            model.openSelection()
            return .handled
        }
        .onKeyPress(.delete) {
            guard !model.currentPath.isEmpty, model.searchText.isEmpty else { return .ignored }
            model.goUp()
            return .handled
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1,
               let id = ids.first,
               let row = model.rows.first(where: { $0.id == id }) {
                Button(row.isDirectory ? "Open Folder" : "Open") {
                    model.activate(ids)
                }
                if !row.isDirectory {
                    Button("Quick Look") {
                        model.selection = ids
                        model.quickLookSelection()
                    }
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(row.path, forType: .string)
                }
                Divider()
            }

            Button("Extract Selected…") {
                model.selection = ids
                model.extractSelected()
            }
            .disabled(ids.isEmpty)

            Button("Extract All…") {
                model.extractAll()
            }

            Divider()

            Button("Show Archive in Finder") {
                model.revealArchive()
            }
        } primaryAction: { ids in
            model.activate(ids)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: emptyIcon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(emptyTitle)
                .font(.title3.weight(.medium))
            Text(emptySubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !model.searchText.isEmpty {
                Button("Clear Search") { model.searchText = "" }
                    .buttonStyle(.link)
                    .padding(.top, 2)
            }
        }
        .padding(30)
    }

    private var emptyIcon: String {
        if !model.searchText.isEmpty { return "magnifyingglass" }
        if model.listing?.entries.isEmpty == true { return "archivebox" }
        return "folder"
    }

    private var emptyTitle: String {
        if !model.searchText.isEmpty { return "No matches" }
        if model.listing?.entries.isEmpty == true { return "This archive is empty" }
        return "This folder is empty"
    }

    private var emptySubtitle: String {
        if !model.searchText.isEmpty {
            return "Nothing in this archive matches “\(model.searchText)”."
        }
        if model.listing?.entries.isEmpty == true {
            return "The archive does not contain any files."
        }
        return "There are no files or folders here."
    }
}
