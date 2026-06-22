import AppKit
import SwiftUI

struct CommandKeyMonitor: NSViewRepresentable {
    let onOpenRepository: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenRepository: onOpenRepository)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onOpenRepository = onOpenRepository
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onOpenRepository: () -> Void
        private var monitor: Any?

        init(onOpenRepository: @escaping () -> Void) {
            self.onOpenRepository = onOpenRepository
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let isCommandO = event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "o"

                if isCommandO {
                    onOpenRepository()
                    return nil
                }

                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
