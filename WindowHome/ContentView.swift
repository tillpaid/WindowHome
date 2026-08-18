//
//  ContentView.swift
//  WindowHome
//
//  Created by Александр Майборода on 24.07.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: SettingsPage? = .home

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
            .navigationTitle("WindowHome")
            .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    SettingsPageView(page: selection ?? .home)
                        .padding(24)
                        .frame(maxWidth: 680, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .top)
                }

                Divider()

                SettingsStatusBar()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .navigationTitle((selection ?? .home).title)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 760, idealWidth: 840, minHeight: 560, idealHeight: 660)
    }
}

private struct SettingsStatusBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(appState.statusMessage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button(appState.statusCopyFeedback.isEmpty ? "Copy" : appState.statusCopyFeedback) {
                appState.copyStatus()
            }
            .font(.footnote)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
