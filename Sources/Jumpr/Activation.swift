import AppKit

/// Ways to bring another app forward, mildest first.
///
/// Since macOS 14 activation is cooperative: an app that is not itself in front can only
/// *ask*, and the system may ignore it. Asking through accessibility (`AXFrontmost`) is
/// ignored on macOS 27: the call succeeds and the app stays in the background. So the
/// presser tries these in order and checks after each whether the app really came forward.
enum Activation {
    /// The public request. Honoured or not at the system's discretion.
    static func activate(_ pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// Opens the already-running app through Launch Services, as the Dock or `open -a` does.
    static func open(_ pid: pid_t) {
        guard let url = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return }
        let c = NSWorkspace.OpenConfiguration()
        c.activates = true
        c.addsToRecentItems = false
        c.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: c, completionHandler: nil)
    }

    /// Asks the window server directly, marked as user generated. Private, and what window
    /// switchers use; looked up at run time so a macOS that drops it costs only this step.
    /// False when the symbols are missing or the call failed.
    @discardableResult
    static func windowServer(_ pid: pid_t, window: CGWindowID) -> Bool {
        guard let getProcessForPID, let setFrontProcess else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == 0 else { return false }
        return setFrontProcess(&psn, window, userGenerated) == 0
    }
}

private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> Int32

private let userGenerated: UInt32 = 0x200  // kCPSUserGenerated

private let getProcessForPID: GetProcessForPID? = {
    guard let s = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID") else { return nil }  // RTLD_DEFAULT
    return unsafeBitCast(s, to: GetProcessForPID.self)
}()

private let setFrontProcess: SetFrontProcess? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let s = dlsym(h, "_SLPSSetFrontProcessWithOptions") else { return nil }
    return unsafeBitCast(s, to: SetFrontProcess.self)
}()
