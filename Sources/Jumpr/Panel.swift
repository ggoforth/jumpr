import AppKit
import JumprCore
import SwiftUI

/// The panel under the menu bar icon, and the only SwiftUI in Jumpr. Every control writes
/// straight to its default; the overlay reads label settings on each trigger, and repaints
/// open labels when a colour changes.
struct PanelView: View {
    var close: () -> Void
    var onRecording: (Bool) -> Void
    var onHotkey: (Hotkey) -> Void
    @ObservedObject var onboarding: Onboarding
    @ObservedObject var loginItem: LoginItem
    @ObservedObject var updater: UpdaterController

    @AppStorage(Keys.paused) private var paused = false
    @AppStorage(Keys.labelSize) private var size = 15.0
    @AppStorage(Keys.labelColor) private var labelHex = "FFD60A"
    @AppStorage(Keys.labelTextColor) private var textHex: String?
    @AppStorage(Keys.labelTextMode) private var textMode: String?
    @AppStorage(Keys.hotkey) private var hotkeyStored = Hotkey.default.stored
    @AppStorage(Keys.scrollHotkey) private var scrollHotkeyStored = Hotkey.defaultScroll.stored
    @AppStorage(Keys.clickKeys) private var clickKeysStored: String?
    @AppStorage(Keys.showReadout) private var showReadout = false
    @AppStorage(Keys.showAdvancedSettings) private var showAdvanced = false
    /// Not stored: the panel opens on Appearance after each launch.
    @State private var tab = PanelTab.appearance

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    private static let issues = URL(string: "https://github.com/ggoforth/jumpr/issues")!

    private var labelRGB: RGB { RGB(hex: labelHex) ?? RGB(hex: "FFD60A")! }
    private var letters: Letters { Letters(storedMode: textMode, storedTextColor: textHex) }
    private var labelColor: Color { Color(labelRGB) }
    private var letterColor: Color { Color(letters.color(on: labelRGB)) }
    private var hotkey: Hotkey { Hotkey(stored: hotkeyStored) ?? .default }
    /// Off while paused, and while Jumpr cannot work at all for want of the permission.
    private var on: Bool { onboarding.trusted && !paused }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !onboarding.trusted {
                permissionBanner
            } else if onboarding.needsRelaunch {
                relaunchBanner
            }
            if updater.updatePending { updateBanner }
            if onboarding.trusted && !onboarding.needsRelaunch { hint }
            LabelPreview(size: clampLabelSize(size), label: labelColor, letters: letterColor)
                .opacity(on ? 1 : 0.45)
            TabBar(selection: $tab, fill: labelColor, text: letterColor)
            switch tab {
            case .appearance: appearance
            case .shortcuts: shortcuts
            case .general: general
            }
            Divider()
            footer
        }
        .frame(width: 320)
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
        .tint(labelColor)
    }

    // MARK: Tabs

    @ViewBuilder private var appearance: some View {
        PalettePicker(label: labelRGB, letters: letters,
                      pickLabel: { labelHex = $0 },
                      pickLetters: { textHex = $0; textMode = LetterMode.color.rawValue },
                      pickAuto: { textMode = LetterMode.auto.rawValue })
        sizeSlider
    }

    @ViewBuilder private var shortcuts: some View {
        HotkeyRecorder(title: "Show labels", hotkey: hotkeyBinding, accent: labelColor, onRecording: onRecording)
        // Applied live by main's watcher on the default, as `defaults write` would be.
        HotkeyRecorder(title: "Scroll",
                       hotkey: Binding(get: { Hotkey(stored: scrollHotkeyStored) ?? .defaultScroll },
                                       set: { scrollHotkeyStored = $0.stored }),
                       accent: labelColor, onRecording: onRecording)
        ClickKeyRows(stored: $clickKeysStored)
    }

    @ViewBuilder private var general: some View {
        settingSwitches
        HStack {
            Text("Version \(Self.version)")
            Spacer()
            Button("Check for Updates…") {
                close()
                updater.checkForUpdates()
            }
            .controlSize(.small)
            .disabled(!updater.canCheckForUpdates)
        }
        .frame(minHeight: 26)
    }

    // MARK: Header and banners

    private var header: some View {
        HStack(spacing: 10) {
            Text("J")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(letterColor)
                .frame(width: 30, height: 30)
                .background(labelColor, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Jumpr").font(.system(size: 15, weight: .semibold))
                Text(Self.version).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(on ? "On" : "Off").font(.system(size: 12)).foregroundStyle(.secondary)
            // Pause inverted. `paused` is the single source of truth; main.swift acts on it.
            Toggle("Jumpr on", isOn: Binding(get: { on }, set: { paused = !$0 }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!onboarding.trusted)
        }
    }

    private var permissionBanner: some View {
        WarningBanner(title: "Jumpr needs Accessibility access",
                      detail: "It uses it to find what you can click and to click it. Turn on Jumpr in the list, then come back.") {
            Button("Open Accessibility Settings") { onboarding.openAccessibilitySettings() }
                .buttonStyle(FilledButtonStyle(background: labelColor, foreground: letterColor))
        }
    }

    /// The grant arrived but the key listener could not start until Jumpr starts again.
    private var relaunchBanner: some View {
        WarningBanner(title: "Jumpr needs a relaunch",
                      detail: "Access is on. Jumpr can use it once it starts again.") {
            Button("Relaunch Jumpr") { onboarding.relaunch() }
                .buttonStyle(FilledButtonStyle(background: labelColor, foreground: letterColor))
        }
    }

    private var updateBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle").font(.system(size: 17)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("An update is ready").fontWeight(.semibold)
                Text("It installs when you say so.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Install") {
                close()
                updater.checkForUpdates()
            }
            .buttonStyle(FilledButtonStyle(background: labelColor, foreground: letterColor))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var hint: some View {
        if on {
            HStack(spacing: 5) {
                Text("Press")
                Keycaps(keys: hotkey.keycaps(keyName: characterForKey), height: 20)
                Text("anywhere to show labels.")
            }
            .foregroundStyle(.secondary)
        } else {
            Text("Paused. The hotkey does nothing until you turn Jumpr back on.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Size and switches

    private var sizeSlider: some View {
        HStack(spacing: 12) {
            Text("Label size").fontWeight(.semibold)
            // No `step`: a stepped slider draws a tick for each of its 23 values. Whole
            // points come from rounding instead.
            Slider(value: Binding(get: { clampLabelSize(size) }, set: { size = $0.rounded() }), in: 10...32) {
                Text("Label size")
            }
            .labelsHidden()
            Text("\(Int(clampLabelSize(size))) pt").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    // Hidden from strangers: the readout still works when set by hand, and the second key
    // shows its switch again:
    //   defaults write com.greggoforth.jumpr showReadout -bool true
    //   defaults write com.greggoforth.jumpr showAdvancedSettings -bool true
    @ViewBuilder private var settingSwitches: some View {
        SwitchRow(title: "Start at login",
                  isOn: Binding(get: { loginItem.enabled }, set: { loginItem.set($0) }))
        if loginItem.needsApproval {
            Note("Allow Jumpr in System Settings › General › Login Items.")
        }
        // Sparkle's own setting; Jumpr stores no copy of it.
        SwitchRow(title: "Check for updates on its own",
                  isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.setAutomaticallyChecks($0) }))
            .disabled(!updater.isConfigured)
        if !updater.isConfigured {
            Note("Updates are off in development builds.")
        }
        if showAdvanced {
            SwitchRow(title: "Show timing readout", isOn: $showReadout)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Report a Problem") {
                close()
                NSWorkspace.shared.open(Self.issues)
            }
            .foregroundStyle(.secondary)
            Spacer()
            Button { NSApp.terminate(nil) } label: {
                HStack(spacing: 6) {
                    Text("Quit")
                    Text("⌘Q").foregroundStyle(.secondary)
                }
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
    }

    private var hotkeyBinding: Binding<Hotkey> {
        Binding(get: { hotkey }, set: { hotkeyStored = $0.stored; onHotkey($0) })
    }
}

// MARK: - Parts

extension Color {
    /// Through sRGB, as the overlay draws it.
    init(_ c: RGB) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b) }
}

/// The panel's sections. One long screen had grown to about 900 pt once each kind of click
/// got a key, so everything under the preview is split three ways.
private enum PanelTab: String, CaseIterable {
    case appearance = "Appearance", shortcuts = "Shortcuts", general = "General"
}

/// The tabs, drawn by hand: a system segmented control cannot fill its selection with the
/// label colour, and here what is selected looks like a label.
private struct TabBar: View {
    @Binding var selection: PanelTab
    let fill: Color
    let text: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                let selected = tab == selection
                Button { selection = tab } label: {
                    Text(tab.rawValue)
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(selected ? text : Color.primary.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(selected ? fill : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A hotkey drawn as one small key per modifier and the key.
struct Keycaps: View {
    let keys: [String]
    let height: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, key.count > 1 ? 6 : 5)
                    .frame(minWidth: height, minHeight: height)
                    .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: height / 4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined())
    }
}

/// The key held on a label's last letter for each kind of click: one row a click, one menu
/// a row. Each row had a five-way picker, twenty segments in a column, which is what split
/// the panel into tabs. Choosing a key another click has swaps the two, so the rows never
/// show one key twice. Read by the controller on the next trigger.
private struct ClickKeyRows: View {
    @Binding var stored: String?

    private var keys: ClickKeys { ClickKeys(stored: stored) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hold on a label's last letter").fontWeight(.semibold)
            Text("Each kind of click takes one key, or none.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(ClickKind.settable, id: \.self) { kind in
                HStack {
                    Text(Self.title(kind))
                    Spacer()
                    Picker(Self.title(kind), selection: Binding(
                        get: { keys.modifier(for: kind) },
                        set: { modifier in
                            var changed = keys
                            changed.set(modifier, for: kind)
                            stored = changed.stored
                        })) {
                        Text("None").tag(ClickModifier?.none)
                        ForEach(ClickModifier.allCases, id: \.self) {
                            Text("\($0.symbol) \($0.name)").tag(ClickModifier?.some($0))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    // One width, so the four menus line up whatever each one shows.
                    .frame(width: 130)
                }
                .frame(minHeight: 26)
            }
        }
    }

    private static func title(_ kind: ClickKind) -> String {
        switch kind {
        case .right: "Right-click"
        case .command: "Command-click"
        case .double: "Double-click"
        case .shift: "Shift-click"
        case .plain: "Click"
        }
    }
}

/// Three sample labels on an abstract window, drawn like `Overlay.add(label:)`: bold
/// monospaced, corner radius size/4, thin dark border.
private struct LabelPreview: View {
    let size: Double
    let label: Color
    let letters: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 9) {
                bar(58, 8, .primary.opacity(0.15))
                bar(44, 8, .primary.opacity(0.09))
                bar(64, 8, .primary.opacity(0.09))
                bar(38, 8, .primary.opacity(0.09))
                bar(52, 8, .primary.opacity(0.09))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .frame(width: 96, height: 128, alignment: .topLeading)
            .background(Color.primary.opacity(0.04))
            VStack(alignment: .leading, spacing: 9) {
                bar(120, 10, .primary.opacity(0.15))
                bar(190, 8, .primary.opacity(0.09))
                bar(160, 8, .primary.opacity(0.09))
                bar(84, 8, label.opacity(0.55))
            }
            .offset(x: 112, y: 14)
            RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.15))
                .frame(width: 74, height: 24)
                .offset(x: 232, y: 90)
            sample("AS").offset(x: 58, y: 26)
            sample("DF").offset(x: 176, y: 58)
        }
        .frame(width: 320, height: 128, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            sample("GK").padding(.trailing, 8).padding(.bottom, 26)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
        .accessibilityElement()
        .accessibilityLabel("Preview of labels at the chosen colors and size")
    }

    private func bar(_ width: CGFloat, _ height: CGFloat, _ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: height / 2).fill(fill).frame(width: width, height: height)
    }

    private func sample(_ text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: size / 4)
        return Text(text)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .foregroundStyle(letters)
            .padding(.horizontal, size * 0.3)
            .background(label, in: shape)
            .overlay(shape.stroke(Color.black.opacity(0.6), lineWidth: 0.5))
            .fixedSize()
    }
}

/// One palette for two colours. "Label" and "Letters" above it say which one a swatch, the
/// hex field, White and Black change. Before it each colour had its own row of presets, a
/// second row behind "More" and an exact-colour field, which was most of the panel's height.
private struct PalettePicker: View {
    let label: RGB
    let letters: Letters
    let pickLabel: (String) -> Void
    let pickLetters: (String) -> Void
    let pickAuto: () -> Void

    private enum Target { case label, letters }

    @State private var target = Target.label
    /// What is typed in the hex field while it is not yet six digits.
    @State private var draft: String?

    private var labelColor: Color { Color(label) }
    private var letterColor: Color { Color(letters.color(on: label)) }

    /// The stored colour of what is being changed; the swatch with this hex shows the ring.
    /// Nil for letters on Auto.
    private var selectedHex: String? {
        switch target {
        case .label: return label.hex
        case .letters:
            if case .color(let c) = letters { return c.hex }
            return nil
        }
    }

    /// What the hex field shows when nothing is being typed: on Auto, the colour Auto gives.
    private var fieldHex: String { target == .label ? label.hex : letters.color(on: label).hex }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            targets
            VStack(spacing: 4) {
                ForEach(Array(Palette.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) { ForEach(row, id: \.hex) { swatch($0) } }
                }
            }
            HStack(spacing: 8) {
                if target == .letters { autoButton }
                hexField
                Spacer()
                swatch(Palette.white).frame(width: 28)
                swatch(target == .label ? Palette.labelBlack : Palette.letterBlack).frame(width: 28)
            }
        }
    }

    // Underlined, not filled: a second filled bar under the panel's tabs would read as the
    // same control twice.
    private var targets: some View {
        HStack(spacing: 0) {
            targetTab(.label, "Label", value: "#\(label.hex)") { labelColor }
            if case .color(let c) = letters {
                targetTab(.letters, "Letters", value: "#\(c.hex)") { Color(c) }
            } else {
                targetTab(.letters, "Letters", value: "Auto") {
                    HStack(spacing: 0) {
                        Color.black
                        Color.white
                    }
                }
            }
        }
        .background(alignment: .bottom) { Color.primary.opacity(0.1).frame(height: 1) }
    }

    private func targetTab<Chip: View>(_ tab: Target, _ title: String, value: String,
                                       @ViewBuilder chip: () -> Chip) -> some View {
        let selected = target == tab
        let shape = RoundedRectangle(cornerRadius: 4)
        return Button {
            target = tab
            draft = nil
        } label: {
            HStack(spacing: 6) {
                chip()
                    .frame(width: 14, height: 14)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.gray.opacity(0.45)))
                Text(title)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(Color.primary.opacity(selected ? 1 : 0.8))
                Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .overlay(alignment: .bottom) { (selected ? labelColor : Color.clear).frame(height: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) color, \(value)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatch(_ s: Swatch) -> some View {
        let selected = selectedHex == s.hex
        let shape = RoundedRectangle(cornerRadius: 5)
        return Button {
            draft = nil
            pick(s.hex)
        } label: {
            Color(RGB(hex: s.hex)!)
                .frame(height: 22)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.gray.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.primary : .clear, lineWidth: 2)
                    .padding(-3))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Auto is not a colour, so it sits beside the hex field and only for the letters.
    /// Selected, it is drawn as a label is: the label colour, with the letters Auto gives.
    private var autoButton: some View {
        let selected = letters == .auto
        return Button {
            draft = nil
            pickAuto()
        } label: {
            Text("Auto")
                .fontWeight(.semibold)
                .foregroundStyle(selected ? letterColor : Color.primary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(selected ? labelColor : Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Automatic")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var hexField: some View {
        HStack(spacing: 5) {
            Text("#").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
            TextField("Hex color", text: Binding(
                get: { draft ?? fieldHex },
                set: { typed in
                    let clean = HexDraft.clean(typed)
                    if let c = HexDraft.color(clean) {
                        draft = nil
                        pick(c.hex)
                    } else {
                        draft = clean
                    }
                }))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 80)
        }
    }

    private func pick(_ hex: String) {
        switch target {
        case .label: pickLabel(hex)
        case .letters: pickLetters(hex)
        }
    }
}

private struct WarningBanner<Action: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).accessibilityHidden(true)
                Text(title).fontWeight(.semibold)
            }
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            action
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.4)))
    }
}

/// The banners' buttons, filled with the label colour and lettered like a label.
private struct FilledButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct SwitchRow: View {
    let title: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
        .frame(minHeight: 26)
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
