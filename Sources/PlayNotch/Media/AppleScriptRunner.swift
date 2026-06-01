import Foundation
import AppKit

/// Thin helper around NSAppleScript for talking to scriptable apps
/// (Music.app, Spotify.app). The first call to a given target app will
/// trigger a macOS Automation (TCC) permission prompt.
enum AppleScriptRunner {
    /// Run a script and return the result descriptor, or nil on error.
    @discardableResult
    static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            // Errors are common (app quitting, no current track) — keep quiet
            // unless we are debugging.
            #if DEBUG
            FileHandle.standardError.write(Data("[AppleScript] \(error)\n".utf8))
            #endif
            return nil
        }
        return result
    }

    /// Run a script that returns a single string value.
    static func string(_ source: String) -> String? {
        run(source)?.stringValue
    }

    /// Parse a number produced by AppleScript's `as string`, which uses the
    /// system locale — so on e.g. an Italian Mac decimals come back with a
    /// comma ("295,28"). `Double` only accepts a dot, so fall back to swapping
    /// the separator.
    static func double(_ s: String?) -> Double? {
        guard let s, !s.isEmpty else { return nil }
        return Double(s) ?? Double(s.replacingOccurrences(of: ",", with: "."))
    }

    /// Check whether an app with the given bundle id is running, without
    /// launching it.
    static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
