import AppKit
import SwiftUI

struct ExtractSheet: View {
    let context: ExtractSheetContext

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var destination: URL
    @State private var overwrite = true
    @State private var revealInFinder = true
    @State private var password = ""
    @State private var job: ExtractionJob?
    @State private var destinationIsCustom = false

    init(context: ExtractSheetContext) {
        self.context = context
        let parent = context.archiveURL.deletingLastPathComponent()
        _destination = State(initialValue: parent.appendingPathComponent(Self.stem(for: context.archiveName),
                                                                         isDirectory: true))
    }

    private static func stem(for name: String) -> String {
        let lowered = name.lowercased()
        for suffix in [".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz2", ".txz", ".zipx"] {
            if lowered.hasSuffix(suffix) {
                return String(name.dropLast(suffix.count))
            }
        }
        let stem = (name as NSString).deletingPathExtension
        return stem.isEmpty ? "Extracted" : stem
    }

    var body: some View {
        Group {
            if let job {
                ExtractionProgressView(job: job,
                                       context: context,
                                       onBack: { withAnimation(.easeInOut(duration: 0.15)) { self.job = nil } },
                                       onDone: { dismiss() })
            } else {
                form
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled(job?.phase == .running)
        .onDisappear {
            if job?.phase == .running { job?.cancel() }
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                destinationSection
                if context.containsEncrypted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(.callout.weight(.medium))
                        SecureField("Password for encrypted items", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    Toggle("Overwrite existing files", isOn: $overwrite)
                    Toggle("Show in Finder when finished", isOn: $revealInFinder)
                }
                .toggleStyle(.checkbox)
                .font(.callout)
            }
            .padding(24)
            Divider()
            footer
        }
        .frame(width: 560)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: FileIcons.archiveIcon())
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Extract “\(context.archiveName)”")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(context.selectionLabel) · \(Formatting.size(context.totalBytes))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination")
                .font(.callout.weight(.medium))
            HStack(spacing: 8) {
                Text(destination.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(.callout, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor)))
                    .help(destination.path)
                Button("Choose…") { chooseDestination() }
            }
            HStack(spacing: 14) {
                Button {
                    destination = context.archiveURL.deletingLastPathComponent()
                        .appendingPathComponent(Self.stem(for: context.archiveName), isDirectory: true)
                    destinationIsCustom = false
                } label: {
                    Label("New folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.link)

                Button {
                    destination = context.archiveURL.deletingLastPathComponent()
                    destinationIsCustom = false
                } label: {
                    Label("Archive folder", systemImage: "folder")
                }
                .buttonStyle(.link)
            }
            .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Extract") { begin() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where to extract the selected items"
        panel.directoryURL = destination.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
            destinationIsCustom = true
        }
    }

    private func begin() {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                model.alertMessage = "A file already exists at the destination path."
                return
            }
        } else {
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                model.alertMessage = "Could not create the destination folder: \(error.localizedDescription)"
                return
            }
        }

        let newJob = ExtractionJob(context: context,
                                   destination: destination,
                                   overwrite: overwrite,
                                   password: password.isEmpty ? nil : password,
                                   revealWhenDone: revealInFinder)
        newJob.onSuccess = { [weak model, password] in
            model?.noteExtraction(password: password)
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            job = newJob
        }
        newJob.start()
    }
}

private struct ExtractionProgressView: View {
    @ObservedObject var job: ExtractionJob
    let context: ExtractSheetContext
    let onBack: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            icon
            VStack(spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
            }

            switch job.phase {
            case .running:
                runningContent
            case .success:
                successContent
            case .failed:
                failedContent
            case .cancelled:
                cancelledContent
            }
        }
        .padding(28)
        .frame(width: 560)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(iconColor.opacity(0.13))
                .frame(width: 76, height: 76)
            Image(systemName: iconName)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(iconColor)
        }
    }

    private var iconColor: Color {
        switch job.phase {
        case .running: return .accentColor
        case .success: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    private var iconName: String {
        switch job.phase {
        case .running: return "arrow.down.doc"
        case .success: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark"
        }
    }

    private var title: String {
        switch job.phase {
        case .running: return job.isCancelling ? "Cancelling…" : "Extracting…"
        case .success: return "Extraction complete"
        case .failed: return "Extraction failed"
        case .cancelled: return "Extraction cancelled"
        }
    }

    private var subtitle: String {
        switch job.phase {
        case .running: return job.currentPath.isEmpty ? context.archiveName : job.currentPath
        case .success: return "\(Formatting.items(context.indices.count)) to \(job.destination.lastPathComponent)"
        case .failed: return job.errorText ?? "An unknown error occurred."
        case .cancelled: return "The partially extracted files were left in place."
        }
    }

    private var runningContent: some View {
        VStack(spacing: 14) {
            ProgressView(value: job.fraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: 440)

            HStack(spacing: 8) {
                Text("\(Formatting.compactSize(job.processedBytes)) of \(Formatting.compactSize(job.totalBytes))")
                Text("•")
                Text(job.speedText)
                Text("•")
                Text(job.remainingText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            Button("Cancel") { job.cancel() }
                .disabled(job.isCancelling)
                .padding(.top, 2)
        }
    }

    private var successContent: some View {
        HStack(spacing: 10) {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([job.destination])
            }
            Button("Done") { onDone() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var failedContent: some View {
        HStack(spacing: 10) {
            Button("Back") { onBack() }
            Button("Done") { onDone() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var cancelledContent: some View {
        Button("Done") { onDone() }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
    }
}
