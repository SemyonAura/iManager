import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: DeviceManager
    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        NavigationView {
            SidebarView()
                .frame(minWidth: 230, idealWidth: 265, maxWidth: 320)
            EmptyStateView()
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
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
