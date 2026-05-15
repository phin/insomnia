import Foundation
import IOKit.pwr_mgt

/// Wraps a single IOKit power assertion of type
/// `kIOPMAssertPreventUserIdleSystemSleep`: the Mac stays awake, but the
/// **display is still allowed to sleep** — exactly what you want when you
/// leave an agent running and go to bed.
///
/// Limitations (documented, not bugs): this only blocks the *idle* sleep
/// timer. Closing a laptop lid, choosing Sleep from the Apple menu, or the
/// power button all still sleep the Mac.
public final class PowerAssertion {
    private var assertionID = IOPMAssertionID(0)

    /// Whether the assertion is currently held.
    public private(set) var isHeld = false
    /// The reason string of the currently-held assertion, if any.
    public private(set) var currentReason: String?

    public init() {}

    /// Acquire the assertion, or re-point it if the reason changed.
    ///
    /// Idempotent: holding with the same reason is a no-op. When the reason
    /// changes, the old assertion is released and a new one created so that
    /// `pmset -g assertions` always shows the current reason.
    public func acquire(reason: String) {
        if isHeld {
            if currentReason == reason { return }
            release()
        }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id)
        if result == kIOReturnSuccess {
            assertionID = id
            isHeld = true
            currentReason = reason
        }
    }

    /// Release the assertion if held. Idempotent. A leaked assertion keeps the
    /// Mac awake until reboot, so the app must call this on quit.
    public func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        isHeld = false
        currentReason = nil
    }

    /// Apply a reconcile decision: hold the assertion (with its reason) or
    /// release it.
    public func apply(_ decision: ReconcileDecision) {
        if decision.shouldKeepAwake {
            acquire(reason: decision.reason)
        } else {
            release()
        }
    }

    deinit {
        release()
    }
}
