import SwiftUI
import AppKit

struct PersistedWindowSizeModifier: ViewModifier {
    @AppStorage private var storedWidth: Double
    @AppStorage private var storedHeight: Double

    let minSize: CGSize
    let maxSize: CGSize

    init(
        widthKey: String,
        heightKey: String,
        defaultSize: CGSize,
        minSize: CGSize,
        maxSize: CGSize
    ) {
        _storedWidth = AppStorage(wrappedValue: defaultSize.width, widthKey)
        _storedHeight = AppStorage(wrappedValue: defaultSize.height, heightKey)
        self.minSize = minSize
        self.maxSize = maxSize
    }

    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: minSize.width,
                idealWidth: clampedWidth,
                maxWidth: maxSize.width,
                minHeight: minSize.height,
                idealHeight: clampedHeight,
                maxHeight: maxSize.height
            )
            .background(
                WindowSizeObserver { size in
                    let width = min(max(size.width, minSize.width), maxSize.width)
                    let height = min(max(size.height, minSize.height), maxSize.height)
                    guard abs(width - storedWidth) > 0.5 || abs(height - storedHeight) > 0.5 else {
                        return
                    }

                    storedWidth = width
                    storedHeight = height
                }
            )
    }

    private var clampedWidth: CGFloat {
        min(max(CGFloat(storedWidth), minSize.width), maxSize.width)
    }

    private var clampedHeight: CGFloat {
        min(max(CGFloat(storedHeight), minSize.height), maxSize.height)
    }
}

private struct WindowSizeObserver: NSViewRepresentable {
    let onSizeChange: (CGSize) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onSizeChange = onSizeChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onSizeChange = onSizeChange
        nsView.reportCurrentSize()
    }
}

private final class TrackingView: NSView {
    var onSizeChange: ((CGSize) -> Void)?
    private var resizeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detachObserver()

        guard let window else {
            return
        }

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.reportCurrentSize()
        }

        DispatchQueue.main.async { [weak self] in
            self?.reportCurrentSize()
        }
    }

    deinit {
        detachObserver()
    }

    func reportCurrentSize() {
        guard let window else {
            return
        }

        let size = window.contentView?.bounds.size ?? bounds.size
        onSizeChange?(size)
    }

    private func detachObserver() {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
    }
}

extension View {
    func persistedWindowSize(
        widthKey: String,
        heightKey: String,
        defaultSize: CGSize,
        minSize: CGSize,
        maxSize: CGSize
    ) -> some View {
        modifier(
            PersistedWindowSizeModifier(
                widthKey: widthKey,
                heightKey: heightKey,
                defaultSize: defaultSize,
                minSize: minSize,
                maxSize: maxSize
            )
        )
    }
}
