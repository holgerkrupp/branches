import CoreServices
import Foundation

@MainActor
final class RepositoryChangeMonitor {
    private let onChange: () -> Void
    private let debounce: Duration
    private var stream: FSEventStreamRef?
    private var streamRetainsSelf = false
    private var pendingChange: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(250), onChange: @escaping () -> Void) {
        self.debounce = debounce
        self.onChange = onChange
    }

    func startMonitoring(_ url: URL) {
        stopMonitoring()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        streamRetainsSelf = true

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, contextInfo, eventCount, _, _, _ in
                guard eventCount > 0, let contextInfo else { return }

                let monitor = Unmanaged<RepositoryChangeMonitor>
                    .fromOpaque(contextInfo)
                    .takeUnretainedValue()

                MainActor.assumeIsolated {
                    monitor.repositoryDidChange()
                }
            },
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else {
            releaseStreamRetain()
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)

        if !FSEventStreamStart(stream) {
            stopMonitoring()
        }
    }

    func stopMonitoring() {
        pendingChange?.cancel()
        pendingChange = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }

        releaseStreamRetain()
    }

    fileprivate func repositoryDidChange() {
        pendingChange?.cancel()
        pendingChange = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
                onChange()
            } catch { }
        }
    }

    private func releaseStreamRetain() {
        guard streamRetainsSelf else { return }
        streamRetainsSelf = false
        Unmanaged.passUnretained(self).release()
    }
}
