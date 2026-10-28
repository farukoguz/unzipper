import AppKit
import Foundation
import UnzipperCore

@MainActor
final class ExtractionJob: ObservableObject, Identifiable {
    enum Phase: Equatable {
        case running
        case success
        case failed
        case cancelled
    }

    let id = UUID()
    let context: ExtractSheetContext
    let destination: URL
    let overwrite: Bool
    let password: String?
    let revealWhenDone: Bool

    @Published var phase: Phase = .running
    @Published var fraction: Double = 0
    @Published var currentPath = ""
    @Published var processedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var entriesDone = 0
    @Published var entriesTotal = 0
    @Published var speed: Double = 0
    @Published var errorText: String?
    @Published var isCancelling = false

    var onSuccess: (() -> Void)?

    private let cancelFlag = CancelFlag()
    private var started = false
    private var lastSampleTime = Date()
    private var lastSampleBytes: Int64 = 0

    init(context: ExtractSheetContext,
         destination: URL,
         overwrite: Bool,
         password: String?,
         revealWhenDone: Bool) {
        self.context = context
        self.destination = destination
        self.overwrite = overwrite
        self.password = password
        self.revealWhenDone = revealWhenDone
        self.totalBytes = context.totalBytes
        self.entriesTotal = context.totalEntries
    }

    func start() {
        guard !started else { return }
        started = true
        lastSampleTime = Date()
        lastSampleBytes = 0
        Task { await run() }
    }

    func cancel() {
        isCancelling = true
        cancelFlag.cancel()
    }

    private func run() async {
        let request = ExtractionRequest(archiveURL: context.archiveURL,
                                        destination: destination,
                                        entryIndices: context.indices,
                                        totalEntries: context.totalEntries,
                                        password: password?.isEmpty == false ? password : nil,
                                        overwrite: overwrite,
                                        totalBytes: context.totalBytes)
        do {
            try await ArchiveService.extract(request, cancelFlag: cancelFlag) { [weak self] update in
                Task { @MainActor in self?.apply(update) }
            }
            processedBytes = totalBytes
            fraction = 1
            phase = .success
            onSuccess?()
            if revealWhenDone {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        } catch ArchiveError.cancelled {
            phase = .cancelled
        } catch {
            errorText = error.localizedDescription
            phase = .failed
        }
    }

    private func apply(_ update: ProgressUpdate) {
        guard phase == .running else { return }
        if update.totalBytes > 0 { totalBytes = update.totalBytes }
        if update.entriesTotal > 0 { entriesTotal = update.entriesTotal }
        processedBytes = update.completedBytes
        entriesDone = update.entriesDone
        if !update.currentPath.isEmpty { currentPath = update.currentPath }
        fraction = update.fraction

        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleTime)
        if elapsed >= 0.25 {
            let delta = Double(processedBytes - lastSampleBytes)
            let instant = max(0, delta / elapsed)
            speed = speed == 0 ? instant : (speed * 0.72) + (instant * 0.28)
            lastSampleTime = now
            lastSampleBytes = processedBytes
        }
    }

    var speedText: String {
        guard speed > 1 else { return "—" }
        return Formatting.compactSize(Int64(speed)) + "/s"
    }

    var remainingText: String {
        guard speed > 1, totalBytes > processedBytes else { return "—" }
        let seconds = Int(Double(totalBytes - processedBytes) / speed)
        if seconds < 60 { return "\(max(1, seconds))s left" }
        return "\(seconds / 60)m \(seconds % 60)s left"
    }
}

@MainActor
final class CreationJob: ObservableObject, Identifiable {
    enum Phase: Equatable {
        case scanning
        case writing
        case success
        case failed
        case cancelled
    }

    let id = UUID()
    let items: [URL]
    let destination: URL
    let format: ArchiveFormat
    let level: Int

    @Published var phase: Phase = .scanning
    @Published var fraction: Double = 0
    @Published var foundItems = 0
    @Published var currentPath = ""
    @Published var processedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var errorText: String?
    @Published var isCancelling = false

    var onSuccess: (() -> Void)?

    private let cancelFlag = CancelFlag()
    private var started = false

    init(items: [URL], destination: URL, format: ArchiveFormat, level: Int) {
        self.items = items
        self.destination = destination
        self.format = format
        self.level = level
    }

    func start() {
        guard !started else { return }
        started = true
        Task { await run() }
    }

    func cancel() {
        isCancelling = true
        cancelFlag.cancel()
    }

    private func run() async {
        let request = CreationRequest(destination: destination,
                                      items: items,
                                      format: format,
                                      compressionLevel: level)
        do {
            _ = try await ArchiveService.create(request, cancelFlag: cancelFlag) { [weak self] phaseUpdate in
                Task { @MainActor in self?.apply(phaseUpdate) }
            }
            phase = .success
            fraction = 1
            onSuccess?()
        } catch ArchiveError.cancelled {
            phase = .cancelled
        } catch {
            errorText = error.localizedDescription
            phase = .failed
        }
    }

    private func apply(_ update: CreationPhase) {
        switch update {
        case .scanning(let found, let path):
            guard phase == .scanning else { return }
            foundItems = found
            if !path.isEmpty { currentPath = path }
        case .writing(let progress):
            guard phase == .scanning || phase == .writing else { return }
            phase = .writing
            fraction = progress.fraction
            processedBytes = progress.completedBytes
            totalBytes = progress.totalBytes
            if !progress.currentPath.isEmpty { currentPath = progress.currentPath }
        }
    }
}
