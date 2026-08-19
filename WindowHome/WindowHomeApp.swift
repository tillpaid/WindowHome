//
//  WindowHomeApp.swift
//  WindowHome
//
//  Created by Александр Майборода on 24.07.2026.
//

import AppKit
import SwiftUI

@main
struct WindowHomeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("WindowHome", systemImage: "rectangle.on.rectangle") {
            Button("Save Home") { appState.saveHome() }
                .disabled(!appState.permissionGranted)
            Button("Restore Home") { appState.restoreHome() }
                .disabled(!appState.permissionGranted)
            Button("Undo Home") { appState.undoHome() }
                .disabled(!appState.permissionGranted)
            Button("Redo Home") { appState.redoHome() }
                .disabled(!appState.permissionGranted)
            Button("Restore All Windows") { appState.restoreAllHomePositions() }
                .disabled(!appState.permissionGranted)
            Divider()
            Text(appState.permissionGranted ? "Accessibility enabled" : "Accessibility required")
                .foregroundStyle(appState.permissionGranted ? .green : .orange)
            SettingsMenuButton()
            Divider()
            Button("Quit WindowHome") {
                NSApp.terminate(nil)
            }
        }

        Settings {
            ContentView()
                .environmentObject(appState)
        }
    }
}

private struct SettingsMenuButton: View {
    @ViewBuilder
    var body: some View {
        if #available(macOS 14.0, *) {
            ModernSettingsMenuButton()
        } else {
            Button("Settings…") {
                SettingsAppSwitcher.openSettings {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }
    }
}

@available(macOS 14.0, *)
private struct ModernSettingsMenuButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            SettingsAppSwitcher.openSettings {
                openSettings()
            }
        }
    }
}

@MainActor
private enum SettingsAppSwitcher {
    private static var closeObserver: NSObjectProtocol?

    static func showInAppSwitcher() {
        NSApp.setActivationPolicy(.regular)
    }

    static func openSettings(using action: () -> Void) {
        showInAppSwitcher()
        NSApp.activate(ignoringOtherApps: true)
        action()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let settingsWindow = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) else { return }
            observeClose(of: settingsWindow)
            settingsWindow.makeKeyAndOrderFront(nil)
        }
    }

    static func observeClose(of window: NSWindow) {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
