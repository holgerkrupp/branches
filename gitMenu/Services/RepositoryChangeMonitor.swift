import CoreServices
import Foundation

@MainActor
final class RepositoryChangeMonitor {
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?
    private var streamRetainsSelf = false

    init(onChange: @escaping () -> Void) {
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
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }

        releaseStreamRetain()
    }

    fileprivate func repositoryDidChange() {
        onChange()
    }

    private func releaseStreamRetain() {
        guard streamRetainsSelf else { return }
        streamRetainsSelf = false
        Unmanaged.passUnretained(self).release()
    }
}
