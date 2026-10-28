import CSArchive
import CoreFoundation
import Foundation

typealias UZProgressCallbackC = @convention(c) (UnsafeMutableRawPointer?,
                                                UnsafePointer<CChar>?,
                                                Int64,
                                                Int64,
                                                Int32,
                                                Int32) -> Int32

func takeCString(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
    guard let pointer else { return nil }
    defer { uz_free_string(pointer) }
    return String(cString: pointer)
}

func takeError(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
    takeCString(pointer)
}

final class ProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmission: CFAbsoluteTime = 0
    private let cancelFlag: CancelFlag
    private let handler: @Sendable (ProgressUpdate) -> Void
    private var hasEmitted = false

    init(cancelFlag: CancelFlag, handler: @escaping @Sendable (ProgressUpdate) -> Void) {
        self.cancelFlag = cancelFlag
        self.handler = handler
    }

    func report(path: String,
                done: Int64,
                total: Int64,
                entriesDone: Int,
                entriesTotal: Int) -> Bool {
        if cancelFlag.isCancelled { return false }

        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let shouldEmit = !hasEmitted || now - lastEmission >= 0.05 || (total > 0 && done >= total)
        if shouldEmit {
            hasEmitted = true
            lastEmission = now
        }
        lock.unlock()

        if shouldEmit {
            handler(ProgressUpdate(currentPath: path,
                                   completedBytes: done,
                                   totalBytes: total,
                                   entriesDone: entriesDone,
                                   entriesTotal: entriesTotal))
        }
        return !cancelFlag.isCancelled
    }
}

private func uzProgressTrampoline(_ context: UnsafeMutableRawPointer?,
                                  _ path: UnsafePointer<CChar>?,
                                  _ done: Int64,
                                  _ total: Int64,
                                  _ entriesDone: Int32,
                                  _ entriesTotal: Int32) -> Int32 {
    guard let context else { return 1 }
    let relay = Unmanaged<ProgressRelay>.fromOpaque(context).takeUnretainedValue()
    let name = path.map { String(cString: $0) } ?? ""
    let keepGoing = relay.report(path: name,
                                 done: done,
                                 total: total,
                                 entriesDone: Int(entriesDone),
                                 entriesTotal: Int(entriesTotal))
    return keepGoing ? 1 : 0
}

func makeCProgress(_ relay: ProgressRelay) -> UZProgress {
    UZProgress(callback: uzProgressTrampoline,
               context: Unmanaged.passUnretained(relay).toOpaque())
}
