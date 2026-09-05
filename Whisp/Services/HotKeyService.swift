import AppKit
import Foundation

@MainActor
final class HotKeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var onRecordToggle: (() -> Void)?
    var onFinish: (() -> Void)?
    private var recordShortcut = Shortcut.parse("⌥⌘R")
    private var finishShortcut = Shortcut.parse("⌥⌘.")

    func configure(record: String, finish: String) {
        recordShortcut = Shortcut.parse(record)
        finishShortcut = Shortcut.parse(finish)
    }

    func install() {
        uninstall()
        // `addGlobalMonitorForEvents` creates a system-wide event tap. On the
        // current macOS beta an ad-hoc signed app launched from a downloaded
        // DMG can stop receiving window events after that tap is installed.
        // Keep shortcuts scoped to an active Whisp window until the public
        // distribution is signed and notarized with a Developer ID.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func uninstall() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        if recordShortcut.matches(event) { onRecordToggle?() }
        if finishShortcut.matches(event) { onFinish?() }
    }
}

private struct Shortcut {
    var modifiers: NSEvent.ModifierFlags
    var character: String

    static func parse(_ value: String) -> Shortcut {
        var modifiers: NSEvent.ModifierFlags = []
        if value.contains("⌘") { modifiers.insert(.command) }
        if value.contains("⌥") { modifiers.insert(.option) }
        if value.contains("⌃") { modifiers.insert(.control) }
        if value.contains("⇧") { modifiers.insert(.shift) }
        let symbols = CharacterSet(charactersIn: "⌘⌥⌃⇧ ")
        let character = value.components(separatedBy: symbols).joined().lowercased()
        return Shortcut(modifiers: modifiers, character: character)
    }

    func matches(_ event: NSEvent) -> Bool {
        let actual = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return actual == modifiers && event.charactersIgnoringModifiers?.lowercased() == character
    }
}
