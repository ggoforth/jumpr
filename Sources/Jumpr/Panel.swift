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
    @AppStorage(Keys.showReadout) private var showReadout = false
    @AppStorage(Keys.showAdvancedSettings) private var showAdvanced = false

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
            SwatchPicker(title: "Label color", first: Palette.labelColors, more: Palette.moreLabelColors,
                         selectedHex: labelRGB.hex, fieldHex: labelRGB.hex,
                         pick: { labelHex = $0 })
            SwatchPicker(title: "Letter color", first: Palette.letterColors, more: Palette.moreLetterColors,
                         autoSelected: letters == .auto,
                         selectedHex: letterHex, fieldHex: letters.color(on: labelRGB).hex,
                         pick: { textHex = $0; textMode = LetterMode.color.rawValue },
                         pickAuto: { textMode = LetterMode.auto.rawValue })
            sizeSlider
            Divider()
            HotkeyRecorder(hotkey: hotkeyBinding, accent: labelColor, onRecording: onRecording)
            settingSwitches
            Divider()
            footer
        }
        .frame(width: 320)
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
        .tint(labelColor)
    }

    private var letterHex: String? {
        if case .color(let c) = letters { return c.hex }
        return nil
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
        VStack(spacing: 6) {
            HStack {
                Text("Label size").fontWeight(.semibold)
                Spacer()
                Text("\(Int(clampLabelSize(size))) pt").foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 10) {
                Text("A").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { clampLabelSize(size) }, set: { size = $0 }), in: 10...32, step: 1) {
                    Text("Label size")
                }
                .labelsHidden()
                Text("A").font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
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
            Button("Check for Updates…") {
                close()
                updater.checkForUpdates()
            }
            .foregroundStyle(.secondary)
            .disabled(!updater.canCheckForUpdates)
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

/// A row of preset colours, six more behind "More", and an "Exact color" field. With
/// `pickAuto`, the first choice is Auto rather than a colour.
private struct SwatchPicker: View {
    let title: String
    let first: [Swatch]
    let more: [Swatch]
    var autoSelected = false
    /// The stored colour; the swatch with this hex shows the ring. Nil while on Auto.
    let selectedHex: String?
    /// What the exact-colour field shows when nothing is being typed.
    let fieldHex: String
    let pick: (String) -> Void
    var pickAuto: (() -> Void)?

    @State private var expanded = false
    /// What is typed in the field while it is not yet six digits.
    @State private var draft: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Button { expanded.toggle() } label: {
                    HStack(spacing: 3) {
                        Text(expanded ? "Fewer" : "More")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityLabel(expanded ? "Fewer \(title.lowercased())s" : "More \(title.lowercased())s")
            }
            HStack(spacing: 8) {
                if let pickAuto {
                    cell(name: "Automatic", selected: autoSelected) {
                        draft = nil
                        pickAuto()
                    } fill: { AutoSwatch() }
                }
                ForEach(first, id: \.hex) { swatch($0) }
            }
            if expanded {
                HStack(spacing: 8) { ForEach(more, id: \.hex) { swatch($0) } }
                exactField
            }
        }
    }

    private func swatch(_ s: Swatch) -> some View {
        cell(name: s.name, selected: !autoSelected && selectedHex == s.hex) {
            draft = nil
            pick(s.hex)
        } fill: { Color(RGB(hex: s.hex)!) }
    }

    private func cell<Fill: View>(name: String, selected: Bool, action: @escaping () -> Void,
                                  @ViewBuilder fill: () -> Fill) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9)
        return Button(action: action) {
            fill()
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.gray.opacity(0.45)))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? Color.primary : .clear, lineWidth: 2)
                    .padding(-4))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var exactField: some View {
        HStack(spacing: 8) {
            Text("Exact color").foregroundStyle(.secondary)
            Spacer()
            Text("#").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
            TextField("Exact color", text: Binding(
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
                .frame(width: 86)
        }
    }
}

/// The Auto choice: half black, half white, with a small A, so it reads as "whichever fits".
private struct AutoSwatch: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.black
            Color.white
        }
        .overlay(
            Text("A")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.gray))
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
