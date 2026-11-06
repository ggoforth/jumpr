import AppKit
import JumprCore
import SwiftUI

/// The only SwiftUI in Jumpr. Every control writes straight to its default; the
/// overlay reads label settings on each trigger.
struct SettingsView: View {
    var onRecording: (Bool) -> Void
    var onHotkey: (Hotkey) -> Void
    @ObservedObject var onboarding: Onboarding
    @ObservedObject var loginItem: LoginItem

    @AppStorage(Keys.labelSize) private var size = 15.0
    @AppStorage(Keys.labelColor) private var labelHex = "FFD60A"
    @AppStorage(Keys.labelTextColor) private var textHex = "000000"
    @AppStorage(Keys.hotkey) private var hotkeyStored = Hotkey.default.stored
    @AppStorage(Keys.batteryMode) private var battery = BatteryMode.frontApp.rawValue
    @AppStorage(Keys.showReadout) private var showReadout = false
    @AppStorage(Keys.showAdvancedSettings) private var showAdvanced = false

    var body: some View {
        Form {
            Section("Permission") { permission }
            Section("Labels") {
                HStack {
                    Slider(value: sizeBinding, in: 10...32, step: 1) { Text("Label size") }
                    Text("\(Int(clampLabelSize(size))) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                ColorPicker("Label color", selection: color($labelHex, fallback: "FFD60A"), supportsOpacity: false)
                ColorPicker("Text color", selection: color($textHex, fallback: "000000"), supportsOpacity: false)
                LabeledContent("Preview") { preview }
            }
            Section("Hotkey") {
                HotkeyRecorder(hotkey: hotkeyBinding, onRecording: onRecording)
            }
            // Hidden from strangers; both still work when set by hand, and the third key
            // shows them again:
            //   defaults write com.greggoforth.jumpr batteryMode -string full|frontApp|onDemand
            //   defaults write com.greggoforth.jumpr showReadout -bool true
            //   defaults write com.greggoforth.jumpr showAdvancedSettings -bool true
            if showAdvanced {
                Section("On battery") {
                    Picker("On battery", selection: $battery) {
                        Text("Full speed").tag(BatteryMode.full.rawValue)
                        Text("Front app only").tag(BatteryMode.frontApp.rawValue)
                        Text("Scan on demand").tag(BatteryMode.onDemand.rawValue)
                    }
                }
            }
            Section("General") {
                Toggle("Start at login", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.set($0) }))
                if loginItem.needsApproval {
                    Text("Allow Jumpr in System Settings › General › Login Items.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if showAdvanced { Toggle("Show timing readout", isOn: $showReadout) }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)  // grouped forms report no height
    }

    @ViewBuilder private var permission: some View {
        if onboarding.trusted {
            Label("Jumpr can see and click your apps", systemImage: "checkmark.circle.fill")
            if onboarding.needsRelaunch {
                Button("Relaunch Jumpr") { onboarding.relaunch() }
            } else {
                let shortcut = (Hotkey(stored: hotkeyStored) ?? .default).display(keyName: characterForKey)
                Text("Press \(shortcut) to try it").foregroundStyle(.secondary)
            }
        } else {
            Label("Jumpr needs Accessibility access", systemImage: "exclamationmark.triangle.fill")
            Text("Turn on Jumpr in the list, then come back here.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Open Accessibility Settings") { onboarding.openAccessibilitySettings() }
        }
    }

    /// Drawn like `Overlay.add(label:)`: bold monospaced, corner radius size/4, thin dark border.
    private var preview: some View {
        let s = clampLabelSize(size)
        let shape = RoundedRectangle(cornerRadius: s / 4)
        return Text("AK")
            .font(.system(size: s, weight: .bold, design: .monospaced))
            .foregroundStyle(color($textHex, fallback: "000000").wrappedValue)
            .padding(.horizontal, s * 0.3)
            .background(color($labelHex, fallback: "FFD60A").wrappedValue, in: shape)
            .overlay(shape.stroke(Color.black.opacity(0.6), lineWidth: 0.5))
    }

    private var sizeBinding: Binding<Double> {
        Binding(get: { clampLabelSize(size) }, set: { size = $0 })
    }

    private var hotkeyBinding: Binding<Hotkey> {
        Binding(get: { Hotkey(stored: hotkeyStored) ?? .default },
                set: { hotkeyStored = $0.stored; onHotkey($0) })
    }

    /// Hex string <-> Color, converting through sRGB.
    private func color(_ hex: Binding<String>, fallback: String) -> Binding<Color> {
        Binding(
            get: {
                let c = RGB(hex: hex.wrappedValue) ?? RGB(hex: fallback)!
                return Color(.sRGB, red: c.r, green: c.g, blue: c.b)
            },
            set: { new in
                guard let c = NSColor(new).usingColorSpace(.sRGB) else { return }
                hex.wrappedValue = RGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent).hex
            })
    }
}

/// One Settings window for the life of the app, reused on every open.
final class SettingsWindow {
    static let size = NSSize(width: 440, height: 660)

    private let onRecording: (Bool) -> Void
    private let onHotkey: (Hotkey) -> Void
    private let onboarding: Onboarding
    private let loginItem: LoginItem
    private var window: NSWindow?

    init(onboarding: Onboarding, loginItem: LoginItem,
         onRecording: @escaping (Bool) -> Void, onHotkey: @escaping (Hotkey) -> Void) {
        self.onboarding = onboarding
        self.loginItem = loginItem
        self.onRecording = onRecording
        self.onHotkey = onHotkey
    }

    func show() {
        loginItem.refresh()  // the status can change outside Jumpr
        if window == nil {
            let root = SettingsView(onRecording: onRecording, onHotkey: onHotkey,
                                    onboarding: onboarding, loginItem: loginItem)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Jumpr Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.setContentSize(Self.size)
            w.center()
            window = w
        }
        // Jumpr is rarely the active app, and making it active is only a request that macOS
        // may refuse; the window would then open behind the active app's windows.
        // `orderFrontRegardless` puts it on top either way.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        if let w = window {
            log("settings: shown, frame \(w.frame.size), content \(w.contentLayoutRect.size)")
        }
    }
}
