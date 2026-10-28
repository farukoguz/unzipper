import AppKit
import SwiftUI
import UnzipperCore
import UniformTypeIdentifiers

struct CreateArchiveSheet: View {
    let context: CreateSheetContext

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var items: [URL]
    @State private var parentDirectory: URL
    @State private var name: String
    @State private var format: ArchiveFormat = .zip
    @State private var level = 6
    @State private var job: CreationJob?
    @State private var pendingDestination: URL?
    @State private var showReplaceAlert = false
    @State private var dropTargeted = false

    init(context: CreateSheetContext) {
        self.context = context
        let initialItems = context.items
        _items = State(initialValue: initialItems)

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        let home = FileManager.default.homeDirectoryForCurrentUser
        _parentDirectory = State(initialValue: initialItems.first?.deletingLastPathComponent() ?? desktop ?? home)

        if initialItems.count == 1, let single = initialItems.first {
            let isDirectory = (try? single.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let base = isDirectory ? single.lastPathComponent : single.deletingPathExtension().lastPathComponent
            _name = State(initialValue: base.isEmpty ? "Archive" : base)
        } else {
            _name = State(initialValue: "Archive")
        }
    }

    var body: some View {
        Group {
            if let job {
                creationProgress(job)
            } else {
                form
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled(job?.phase == .scanning || job?.phase == .writing)
        .onDisappear {
            if job?.phase == .scanning || job?.phase == .writing { job?.cancel() }
        }
        .alert("Replace existing archive?", isPresented: $showReplaceAlert) {
            Button("Replace", role: .destructive) {
                if let destination = pendingDestination { startJob(destination: destination) }
            }
            Button("Cancel", role: .cancel) { pendingDestination = nil }
        } message: {
            Text("“\(pendingDestination?.lastPathComponent ?? "")” already exists. Do you want to replace it?")
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                itemsSection
                settingsSection
            }
            .padding(24)
            Divider()
            footer
        }
        .frame(width: 660)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: FileIcons.archiveIcon())
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Create Archive")
                    .font(.title3.weight(.semibold))
                Text(items.isEmpty ? "Add files or folders to get started" : "\(items.count) \(items.count == 1 ? "item" : "items")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Items")
                    .font(.callout.weight(.medium))
                Spacer()
                Button {
                    chooseFiles()
                } label: {
                    Label("Add Files…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.link)
                Button {
                    chooseFolder()
                } label: {
                    Label("Add Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.link)
            }
            .font(.callout)

            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(dropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                                  lineWidth: dropTargeted ? 2 : 1)

                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("Drop files or folders here")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, url in
                                itemRow(url: url, index: index)
                                if index < items.count - 1 {
                                    Divider().padding(.leading, 34)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(height: 172)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                handleDrop(providers)
            }
        }
    }

    private func itemRow(url: URL, index: Int) -> some View {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return HStack(spacing: 8) {
            Image(nsImage: FileIcons.icon(name: url.lastPathComponent, isDirectory: isDirectory))
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                items.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Format")
                        .font(.callout.weight(.medium))
                    Picker("Format", selection: $format) {
                        ForEach(ArchiveFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Compression")
                        .font(.callout.weight(.medium))
                    Picker("Compression", selection: $level) {
                        Text("Store").tag(0)
                        Text("Fast").tag(1)
                        Text("Normal").tag(6)
                        Text("Maximum").tag(9)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.callout.weight(.medium))
                    HStack(spacing: 0) {
                        TextField("Archive", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Text(".\(format.fileExtension)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }
                    .frame(maxWidth: 260)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Where")
                        .font(.callout.weight(.medium))
                    HStack(spacing: 8) {
                        Text(parentDirectory.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .help(parentDirectory.path)
                        Button("Choose…") { chooseDestinationFolder() }
                    }
                }
            }

            Text(destinationPreview)
                .font(.caption)
                .foregroundStyle(isValid ? Color.secondary : Color.red)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Create") { createTapped() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Validation

    private var cleanedName: String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = result.lowercased()
        for suffix in [".tar.gz", ".tar.bz2", ".tar.xz", ".zip", ".7z", ".tgz", ".tbz2", ".txz"] {
            if lowered.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !cleanedName.isEmpty && !cleanedName.contains("/") && !cleanedName.contains(":") && !items.isEmpty
    }

    private var destinationPreview: String {
        guard isValid else {
            if items.isEmpty { return "Add at least one file or folder." }
            if cleanedName.isEmpty { return "Enter a name for the archive." }
            return "The name cannot contain “/” or “:”."
        }
        return parentDirectory.appendingPathComponent(cleanedName + "." + format.fileExtension).path
    }

    private var destination: URL {
        parentDirectory.appendingPathComponent(cleanedName + "." + format.fileExtension)
    }

    // MARK: - Actions

    private func createTapped() {
        guard isValid else { return }
        let target = destination
        if FileManager.default.fileExists(atPath: target.path) {
            pendingDestination = target
            showReplaceAlert = true
        } else {
            startJob(destination: target)
        }
    }

    private func startJob(destination: URL) {
        pendingDestination = nil
        let unique = uniqueItems(items)
        guard !unique.isEmpty else { return }
        let newJob = CreationJob(items: unique,
                                 destination: destination,
                                 format: format,
                                 level: level)
        newJob.onSuccess = { [weak model] in
            model?.open(destination)
            model?.showToast("Created \(destination.lastPathComponent)")
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            job = newJob
        }
        newJob.start()
    }

    private func creationProgress(_ job: CreationJob) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(progressColor(job).opacity(0.13))
                    .frame(width: 76, height: 76)
                Image(systemName: progressIcon(job))
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(progressColor(job))
            }

            VStack(spacing: 5) {
                Text(progressTitle(job))
                    .font(.title3.weight(.semibold))
                Text(progressSubtitle(job))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: 440)
                    .multilineTextAlignment(.center)
            }

            if job.phase == .scanning {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 440)
                    .overlay(alignment: .bottomTrailing) {
                        Text(Formatting.items(job.foundItems))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .offset(y: 18)
                    }
            } else if job.phase == .writing {
                ProgressView(value: job.fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 440)
                Text("\(Formatting.compactSize(job.processedBytes)) of \(Formatting.compactSize(job.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            actionButtons(job)
                .padding(.top, 2)
        }
        .padding(28)
        .frame(width: 560)
    }

    private func progressColor(_ job: CreationJob) -> Color {
        switch job.phase {
        case .scanning, .writing: return .accentColor
        case .success: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    private func progressIcon(_ job: CreationJob) -> String {
        switch job.phase {
        case .scanning: return "magnifyingglass"
        case .writing: return "archivebox"
        case .success: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark"
        }
    }

    private func progressTitle(_ job: CreationJob) -> String {
        switch job.phase {
        case .scanning: return "Preparing…"
        case .writing: return job.isCancelling ? "Cancelling…" : "Creating archive…"
        case .success: return "Archive created"
        case .failed: return "Could not create archive"
        case .cancelled: return "Creation cancelled"
        }
    }

    private func progressSubtitle(_ job: CreationJob) -> String {
        switch job.phase {
        case .scanning, .writing:
            return job.currentPath.isEmpty ? job.destination.lastPathComponent : job.currentPath
        case .success:
            return job.destination.path
        case .failed:
            return job.errorText ?? "An unknown error occurred."
        case .cancelled:
            return "The partially created archive was removed."
        }
    }

    @ViewBuilder
    private func actionButtons(_ job: CreationJob) -> some View {
        switch job.phase {
        case .scanning, .writing:
            Button("Cancel") { job.cancel() }
                .disabled(job.isCancelling)
        case .success:
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .failed:
            HStack(spacing: 10) {
                Button("Back") { withAnimation { self.job = nil } }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .cancelled:
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Item management

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose files to add to the archive"
        if panel.runModal() == .OK {
            append(panel.urls)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders to add to the archive"
        if panel.runModal() == .OK {
            append(panel.urls)
        }
    }

    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where to save the archive"
        panel.directoryURL = parentDirectory
        if panel.runModal() == .OK, let url = panel.url {
            parentDirectory = url
        }
    }

    private func append(_ urls: [URL]) {
        let wasEmpty = items.isEmpty
        var existing = Set(items.map { $0.standardizedFileURL })
        for url in urls {
            let standardized = url.standardizedFileURL
            if existing.insert(standardized).inserted {
                items.append(standardized)
            }
        }
        if wasEmpty, let first = items.first {
            parentDirectory = first.deletingLastPathComponent()
        }
        if items.count == 1, let single = items.first {
            let isDirectory = (try? single.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if name == "Archive" {
                name = isDirectory ? single.lastPathComponent : single.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func uniqueItems(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0.standardizedFileURL).inserted }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var dropped: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                }
                if let url {
                    lock.lock(); dropped.append(url); lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            append(dropped)
        }
        return true
    }
}
