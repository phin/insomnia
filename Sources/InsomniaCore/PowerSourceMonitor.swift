import Foundation
import IOKit.ps

/// Reports whether the Mac is on AC power, and notifies when that changes — so
/// the app can re-reconcile the moment a charger is plugged or unplugged (which
/// matters when "Only on AC Power" is enabled).
public final class PowerSourceMonitor {
    private let onChange: () -> Void
    private var runLoopSource: CFRunLoopSource?

    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    /// True if the Mac is on AC power. Desktop Macs (no battery) always report
    /// true. On any uncertainty, returns true — the fail-safe direction for a
    /// keep-awake utility.
    public static var isOnACPower: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else {
            return true
        }
        return (type as String) != (kIOPSBatteryPowerValue as String)
    }

    /// Begin observing power-source changes. The callback is delivered on the
    /// main run loop, so `onChange` runs on the main thread.
    public func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { rawContext in
            guard let rawContext else { return }
            let monitor = Unmanaged<PowerSourceMonitor>
                .fromOpaque(rawContext).takeUnretainedValue()
            monitor.onChange()
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?
            .takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
    }

    deinit {
        stop()
    }
}
