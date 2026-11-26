import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: DeviceManager
    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 265, max: 320)
        } detail: {
            if manager.selectedDeviceID == "appstore" {
                StoreView()
            } else if manager.selectedDeviceID == "downloads" {
                DownloadsView()
            } else if let device = manager.devices.first(where: { $0.id == manager.selectedDeviceID }) {
                DeviceDetailView(device: device)
                    .id(device.id)
            } else {
                EmptyStateView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    settings.present()
                } label: {
                    Label(L("Настройки"), systemImage: "gearshape")
                }
                .help(Text(L("Настройки…")))
            }
        }
        .sheet(isPresented: $settings.isPresented) {
            SettingsView()
        }
    }
}
