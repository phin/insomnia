import Foundation

/// Watches the sessions directory for entry add/remove/rename using a kqueue
/// `DispatchSource`, debounced. This is the low-latency trigger for reconcile;
/// the periodic `ReconcileTimer` is the correctness backstop.
///
/// `insomnia-hook` writes session files via temp-file + `rename()`, and a
/// rename is a directory-level event — so every hook write reliably wakes this
/// watcher. `onChange` is always delivered on the main queue.
final class SessionWatcher {
    private let directory: URL
    private let debounce: TimeInterval
    private let onChange: () -> Void

    private let queue = DispatchQueue(label: "app.insomnia.session-watcher")
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceItem: DispatchWorkItem?

    init(directory: URL, debounce: TimeInterval = 0.3, onChange: @escaping () -> Void) {
        self.directory = directory
        self.debounce = debounce
        self.onChange = onChange
    }

    func start() {
        queue.async { [weak self] in self?.arm() }
    }

    func stop() {
        queue.async { [weak self] in self?.disarm() }
    }

    // MARK: - kqueue plumbing (all on `queue`)

    private func arm() {
        disarm()
        // The directory must exist before we can open it for watching.
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        fileDescriptor = descriptor

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue)
        src.setEventHandler { [weak self] in self?.handleEvent() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 { close(fd) }
            self?.fileDescriptor = -1
        }
        source = src
        src.resume()
    }

    private func disarm() {
        debounceItem?.cancel()
        debounceItem = nil
        source?.cancel()
        source = nil
    }

    private func handleEvent() {
        let flags = source?.data ?? []
        // If the directory itself was replaced, re-open it.
        if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
            arm()
        }
        // Coalesce bursts of writes into a single reconcile.
        debounceItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.onChange() }
        }
        debounceItem = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
