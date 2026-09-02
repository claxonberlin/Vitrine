import Foundation

/// Streams a file with `URLSessionDownloadTask`, surfacing progress, speed
/// and cancel without iterating bytes one by one (the byte-stream approach
/// lost ~99% of throughput because every byte hopped through the executor).
final class DownloadManager: @unchecked Sendable {
    struct Progress: Sendable {
        let received: Int64
        let total: Int64
        let bytesPerSecond: Double
    }

    enum Failure: Error, LocalizedError {
        case canceled
        case http(Int)
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .canceled: return "Download canceled"
            case .http(let code): return "Server returned HTTP \(code)"
            case .underlying(let e): return e.localizedDescription
            }
        }
    }

    private let lock = NSLock()
    private var tasks: [String: URLSessionDownloadTask] = [:]

    func download(
        _ url: URL,
        id: String,
        progress: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        defer { clear(id: id) }
        let delegate = TaskDelegate(progress: progress)
        // 60s for headers, large per-resource budget — Blender DMGs are 300+MB.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60
        config.httpMaximumConnectionsPerHost = 6
        config.networkServiceType = .responsiveData
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                delegate.setContinuation(cont)
                let task = session.downloadTask(with: url)
                self.register(id: id, task: task)
                task.resume()
            }
        } onCancel: {
            self.cancel(id: id)
        }
    }

    func cancel(id: String) {
        lock.lock()
        let task = tasks.removeValue(forKey: id)
        lock.unlock()
        task?.cancel()
    }

    private func register(id: String, task: URLSessionDownloadTask) {
        lock.lock(); defer { lock.unlock() }
        tasks[id] = task
    }

    private func clear(id: String) {
        lock.lock(); defer { lock.unlock() }
        tasks.removeValue(forKey: id)
    }

    private final class TaskDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private var continuation: CheckedContinuation<URL, Error>?
        private let lock = NSLock()
        let progressHandler: (Progress) -> Void
        // Sliding-window EMA for speed: instantaneous bytes-per-second is
        // jittery on fast networks; this smooths it out for display.
        // Sample/emit state is only touched from the session's serial
        // delegate queue, so it needs no locking.
        private var lastSampleTime: Date?
        private var lastSampleBytes: Int64 = 0
        private var smoothedBPS: Double = 0
        private var lastEmitTime: Date = .distantPast

        init(progress: @escaping (Progress) -> Void) {
            self.progressHandler = progress
        }

        func setContinuation(_ cont: CheckedContinuation<URL, Error>) {
            lock.lock()
            continuation = cont
            lock.unlock()
        }

        func urlSession(_ session: URLSession,
                        downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            let now = Date()
            if let last = lastSampleTime {
                let dt = now.timeIntervalSince(last)
                if dt >= 0.25 {
                    let dBytes = Double(totalBytesWritten - lastSampleBytes)
                    let inst = dBytes / dt
                    smoothedBPS = smoothedBPS == 0 ? inst : (0.7 * smoothedBPS + 0.3 * inst)
                    lastSampleTime = now
                    lastSampleBytes = totalBytesWritten
                }
            } else {
                lastSampleTime = now
                lastSampleBytes = totalBytesWritten
            }
            // Forward at most ~10 updates/s. didWriteData can fire hundreds
            // of times per second on a fast link, and each forward becomes a
            // main-actor hop plus a row re-render.
            guard now.timeIntervalSince(lastEmitTime) >= 0.1 else { return }
            lastEmitTime = now
            progressHandler(Progress(
                received: totalBytesWritten,
                total: max(totalBytesExpectedToWrite, totalBytesWritten),
                bytesPerSecond: smoothedBPS
            ))
        }

        func urlSession(_ session: URLSession,
                        downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                resume(.failure(Failure.http(http.statusCode)))
                return
            }
            // The system deletes `location` as soon as this returns, so we
            // move it synchronously to a path the caller controls.
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitrine-\(UUID().uuidString).dmg")
            do {
                try FileManager.default.moveItem(at: location, to: dest)
                resume(.success(dest))
            } catch {
                resume(.failure(Failure.underlying(error)))
            }
        }

        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            session.finishTasksAndInvalidate()
            guard let error else { return }
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                resume(.failure(Failure.canceled))
            } else {
                resume(.failure(Failure.underlying(error)))
            }
        }

        private func resume(_ result: Result<URL, Error>) {
            // Taking the continuation under the lock guarantees exactly one
            // resume even if completion and error callbacks race.
            lock.lock()
            let cont = continuation
            continuation = nil
            lock.unlock()
            guard let cont else { return }
            switch result {
            case .success(let url): cont.resume(returning: url)
            case .failure(let err): cont.resume(throwing: err)
            }
        }
    }
}
