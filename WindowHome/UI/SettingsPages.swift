import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case home
    case shortcuts
    case snapAndResize
    case automation
    case diagnostics

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .shortcuts: "Shortcuts"
        case .snapAndResize: "Snap & Resize"
        case .automation: "Automation"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .shortcuts: "command"
        case .snapAndResize: "rectangle.split.2x1"
        case .automation: "bolt"
        case .diagnostics: "stethoscope"
        }
    }
}

struct SettingsPageView: View {
    let page: SettingsPage

    @ViewBuilder
    var body: some View {
        switch page {
        case .home:
            HomeSettingsPage()
        case .shortcuts:
            ShortcutSettingsPage()
        case .snapAndResize:
            SnapAndResizeSettingsPage()
        case .automation:
            AutomationSettingsPage()
        case .diagnostics:
            DiagnosticsSettingsPage()
        }
    }
}

private struct HomeSettingsPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsPageLayout(
            title: "Home",
            subtitle: "Manage the saved position and size for the currently focused window."
        ) {
            GroupBox("Accessibility") {
                VStack(alignment: .leading, spacing: 12) {
                    PermissionStatusRow(
                        granted: appState.permissionGranted,
                        enabledText: "Accessibility enabled",
                        requiredText: "Accessibility required",
                        actionTitle: appState.permissionGranted ? "Refresh" : "Request Permission",
                        action: appState.permissionGranted
                            ? appState.refreshPermissionStatus
                            : appState.requestAccessibilityPermission
                    )
                    SettingsFootnote("WindowHome uses Accessibility only to read and position application windows.")
                }
                .padding(.vertical, 2)
            }

            GroupBox("Focused Window") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(appState.focusedWindowDescription)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Divider()

                    HStack {
                        Button("Save Home") { appState.saveHome() }
                        Button("Restore Home") { appState.restoreHome() }
                        Button("Undo") { appState.undoHome() }
                        Button("Redo") { appState.redoHome() }
                        Button("Center & Save Home") { appState.centerFocusedWindowAndSaveHome() }
                    }
                    .disabled(!appState.permissionGranted)
                }
                .padding(.vertical, 2)
            }

            SettingsFootnote("Homes are stored separately for each application, display, and effective resolution.")
        }
    }
}

private struct ShortcutSettingsPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsPageLayout(
            title: "Shortcuts",
            subtitle: "Set the global shortcuts used to save, restore, and move windows."
        ) {
            GroupBox("Home") {
                VStack(spacing: 10) {
                    ShortcutSettingRow(title: "Save Home", shortcut: appState.saveHomeShortcut, onRecord: appState.updateSaveHomeShortcut, onClear: appState.clearSaveHomeShortcut)
                    ShortcutSettingRow(title: "Restore Home", shortcut: appState.restoreHomeShortcut, onRecord: appState.updateRestoreHomeShortcut, onClear: appState.clearRestoreHomeShortcut)
                    ShortcutSettingRow(title: "Undo Home", shortcut: appState.undoHomeShortcut, onRecord: appState.updateUndoHomeShortcut, onClear: appState.clearUndoHomeShortcut)
                    ShortcutSettingRow(title: "Redo Home", shortcut: appState.redoHomeShortcut, onRecord: appState.updateRedoHomeShortcut, onClear: appState.clearRedoHomeShortcut)
                    ShortcutSettingRow(title: "Restore All", shortcut: appState.restoreAllShortcut, onRecord: appState.updateRestoreAllShortcut, onClear: appState.clearRestoreAllShortcut)
                    ShortcutSettingRow(title: "Center & Save Home", shortcut: appState.centerAndSaveHomeShortcut, onRecord: appState.updateCenterAndSaveHomeShortcut, onClear: appState.clearCenterAndSaveHomeShortcut)
                }
                .padding(.vertical, 2)
            }

            GroupBox("Displays") {
                VStack(alignment: .leading, spacing: 10) {
                    ShortcutSettingRow(title: "Move to next display", shortcut: appState.moveToNextDisplayShortcut, onRecord: appState.updateMoveToNextDisplayShortcut, onClear: appState.clearMoveToNextDisplayShortcut)
                    ShortcutSettingRow(title: "Move to previous display", shortcut: appState.moveToPreviousDisplayShortcut, onRecord: appState.updateMoveToPreviousDisplayShortcut, onClear: appState.clearMoveToPreviousDisplayShortcut)
                    SettingsFootnote("Display moves wrap around. A saved Home chooses the target position while the current window size is preserved when it fits.")
                }
                .padding(.vertical, 2)
            }

            HStack {
                SettingsFootnote("Select a recorder, then press a key with at least one modifier.")
                Spacer()
                Button("Reset All Shortcuts") { appState.resetShortcuts() }
            }
        }
    }
}

private struct SnapAndResizeSettingsPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsPageLayout(
            title: "Snap & Resize",
            subtitle: "Configure keyboard and mouse window layout behavior."
        ) {
            GroupBox("Keyboard Snap") {
                VStack(alignment: .leading, spacing: 10) {
                    ShortcutSettingRow(title: "Full screen", shortcut: appState.snapFullScreenShortcut, onRecord: appState.updateSnapFullScreenShortcut, onClear: { appState.clearSnapShortcut(.fullScreen) })
                    ShortcutSettingRow(title: "Left", shortcut: appState.snapLeftShortcut, onRecord: appState.updateSnapLeftShortcut, onClear: { appState.clearSnapShortcut(.left) })
                    ShortcutSettingRow(title: "Right", shortcut: appState.snapRightShortcut, onRecord: appState.updateSnapRightShortcut, onClear: { appState.clearSnapShortcut(.right) })
                    ShortcutSettingRow(title: "Top", shortcut: appState.snapTopShortcut, onRecord: appState.updateSnapTopShortcut, onClear: { appState.clearSnapShortcut(.top) })
                    ShortcutSettingRow(title: "Bottom", shortcut: appState.snapBottomShortcut, onRecord: appState.updateSnapBottomShortcut, onClear: { appState.clearSnapShortcut(.bottom) })
                    ShortcutSettingRow(title: "Top left", shortcut: appState.snapTopLeftShortcut, onRecord: appState.updateSnapTopLeftShortcut, onClear: { appState.clearSnapShortcut(.topLeft) })
                    ShortcutSettingRow(title: "Top right", shortcut: appState.snapTopRightShortcut, onRecord: appState.updateSnapTopRightShortcut, onClear: { appState.clearSnapShortcut(.topRight) })
                    ShortcutSettingRow(title: "Bottom left", shortcut: appState.snapBottomLeftShortcut, onRecord: appState.updateSnapBottomLeftShortcut, onClear: { appState.clearSnapShortcut(.bottomLeft) })
                    ShortcutSettingRow(title: "Bottom right", shortcut: appState.snapBottomRightShortcut, onRecord: appState.updateSnapBottomRightShortcut, onClear: { appState.clearSnapShortcut(.bottomRight) })

                    Divider()

                    HStack {
                        Text("Padding")
                        Slider(
                            value: Binding(get: { appState.snapPadding }, set: appState.setSnapPadding),
                            in: 0...80,
                            step: 1
                        )
                        TextField(
                            "Padding",
                            value: Binding(get: { appState.snapPadding }, set: appState.setSnapPadding),
                            format: .number.precision(.fractionLength(0))
                        )
                        .frame(width: 48)
                        Text("pt")
                            .foregroundStyle(.secondary)
                    }
                    SettingsFootnote("Repeat a side or corner shortcut to cycle through 50%, 66%, and 33% widths.")
                }
                .padding(.vertical, 2)
            }

            GroupBox("Centered Resize") {
                VStack(alignment: .leading, spacing: 10) {
                    ShortcutSettingRow(title: "Increase width", shortcut: appState.increaseWidthShortcut, onRecord: appState.updateIncreaseWidthShortcut, onClear: { appState.clearResizeShortcut(.increaseWidth) })
                    ShortcutSettingRow(title: "Decrease width", shortcut: appState.decreaseWidthShortcut, onRecord: appState.updateDecreaseWidthShortcut, onClear: { appState.clearResizeShortcut(.decreaseWidth) })
                    ShortcutSettingRow(title: "Increase height", shortcut: appState.increaseHeightShortcut, onRecord: appState.updateIncreaseHeightShortcut, onClear: { appState.clearResizeShortcut(.increaseHeight) })
                    ShortcutSettingRow(title: "Decrease height", shortcut: appState.decreaseHeightShortcut, onRecord: appState.updateDecreaseHeightShortcut, onClear: { appState.clearResizeShortcut(.decreaseHeight) })

                    Divider()

                    HStack {
                        Text("Resize step")
                        Spacer()
                        TextField(
                            "Step",
                            value: Binding(get: { appState.resizeStep }, set: appState.setResizeStep),
                            format: .number.precision(.fractionLength(0))
                        )
                        .frame(width: 56)
                        Stepper(
                            "Resize step",
                            value: Binding(get: { appState.resizeStep }, set: appState.setResizeStep),
                            in: 1...500,
                            step: 1
                        )
                        .labelsHidden()
                        Text("pt")
                            .foregroundStyle(.secondary)
                    }
                    SettingsFootnote("Each command moves opposite edges equally so the window stays centered. Snapped and tiled windows are unchanged.")
                }
                .padding(.vertical, 2)
            }

            GroupBox("Mouse") {
                VStack(alignment: .leading, spacing: 10) {
                    PermissionStatusRow(
                        granted: appState.inputMonitoringPermissionGranted,
                        enabledText: "Input Monitoring enabled",
                        requiredText: "Input Monitoring required",
                        actionTitle: appState.inputMonitoringPermissionGranted ? "Refresh" : "Request Permission",
                        action: appState.inputMonitoringPermissionGranted
                            ? appState.refreshInputMonitoringPermissionStatus
                            : appState.requestInputMonitoringPermission
                    )
                    SettingsFootnote("Input Monitoring is used only to detect mouse drag boundaries for automatic Home saving and mouse Snap.")

                    Divider()

                    Picker(
                        "Mouse Snap",
                        selection: Binding(get: { appState.mouseSnapMode }, set: appState.setMouseSnapMode)
                    ) {
                        Text("Off").tag(MouseSnapMode.off)
                        Text("Edge + Option").tag(MouseSnapMode.edgeAndOption)
                        Text("Option only").tag(MouseSnapMode.optionOnly)
                    }
                    .pickerStyle(.radioGroup)

                    SettingsFootnote("Edge + Option supports compact edge areas and larger targets while Option is held. Option only requires holding Option for every mouse Snap.")

                    Toggle(
                        "Show Snap activation areas while dragging",
                        isOn: Binding(
                            get: { appState.showMouseSnapAreas },
                            set: appState.setShowMouseSnapAreas
                        )
                    )
                    .disabled(!appState.mouseSnapEnabled)
                    SettingsFootnote("Shows the actual left, right, and full-screen hit boxes. The active area is highlighted more strongly.")

                    Toggle(
                        "Save Home after I move or resize a window with the mouse",
                        isOn: Binding(
                            get: { appState.automaticSaveAfterMouseMoveEnabled },
                            set: appState.setAutomaticSaveAfterMouseMoveEnabled
                        )
                    )
                    SettingsFootnote("Saving happens after mouse release. Full-screen, maximized, and standard half-screen layouts are excluded.")
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct AutomationSettingsPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsPageLayout(
            title: "Automation",
            subtitle: "Choose how WindowHome places a window after moving it to another display."
        ) {
            GroupBox("Display Move") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Restore the full Home after moving a window to another display",
                        isOn: Binding(
                            get: { appState.restoreFullHomeAfterDisplayMoveEnabled },
                            set: appState.setRestoreFullHomeAfterDisplayMoveEnabled
                        )
                    )
                    SettingsFootnote("Applies to WindowHome's Move to Next Display and Move to Previous Display shortcuts. When disabled, regular windows preserve their current size; snapped, tiled, and full-screen-like windows still return to the full destination Home.")
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct DiagnosticsSettingsPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsPageLayout(
            title: "Diagnostics",
            subtitle: "Inspect the focused window and test direct geometry changes."
        ) {
            GroupBox("Focused Window") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(appState.focusedWindowDescription)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Divider()

                    HStack {
                        Button("Read Focused Window") { appState.inspectFocusedWindow() }
                            .keyboardShortcut("i", modifiers: [.command])
                        Button("Apply Test Inset") { appState.applyTestInset() }
                            .disabled(!appState.permissionGranted)
                        Button("Restore Last Read") { appState.restoreLastRead() }
                    }
                }
                .padding(.vertical, 2)
            }

            SettingsFootnote("Apply Test Inset reduces the last-read window frame by 24 points. Restore Last Read returns it to the captured geometry.")
        }
    }
}

private struct SettingsPageLayout<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct PermissionStatusRow: View {
    let granted: Bool
    let enabledText: String
    let requiredText: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            Label(
                granted ? enabledText : requiredText,
                systemImage: granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
            )
            .foregroundStyle(granted ? .green : .orange)
            Spacer()
            Button(actionTitle, action: action)
        }
    }
}

private struct ShortcutSettingRow: View {
    let title: String
    let shortcut: KeyboardShortcut?
    let onRecord: (KeyboardShortcut) -> Void
    let onClear: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 6) {
                ShortcutRecorderView(shortcut: shortcut, onRecord: onRecord)
                    .frame(width: 125, height: 28)
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(shortcut == nil ? .tertiary : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(shortcut == nil)
                .help("Clear shortcut")
            }
        }
    }
}

private struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
