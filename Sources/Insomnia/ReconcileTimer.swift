import Foundation

/// Fires a callback on a fixed interval — the correctness backstop for
/// reconcile. Grace-period expiry is purely time-based and produces no
/// filesystem event, so the watcher alone is not enough.
///
/// `onTick` is always delivered on the main queue.
final class ReconcileTimer {
    private let interval: TimeInterval
    private let onTick: () -> Void
    private let queue = DispatchQueue(label: "app.insomnia.reconcile-timer")
    private var timer: DispatchSourceTimer?

    init(interval: TimeInterval = 10, onTick: @escaping () -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(1))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.onTick() }
        }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
