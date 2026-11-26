import SwiftUI

enum DeviceSection: String, CaseIterable, Identifiable {
    case overview
    case apps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("Обзор")
        case .apps: return L("Приложения")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "info.circle"
        case .apps: return "square.grid.2x2"
        }
    }
}

struct DeviceDetailView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let device: Device

    @EnvironmentObject private var manager: DeviceManager
    @AppStorage("selectedDeviceSection") private var sectionRaw: String = DeviceSection.overview.rawValue

    private var section: Binding<DeviceSection> {
        Binding(
            get: { DeviceSection(rawValue: sectionRaw) ?? .overview },
            set: { sectionRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DeviceHeader(device: device)

                Picker(L("Раздел"), selection: section) {
                    ForEach(DeviceSection.allCases) { item in
                        Label(item.title, systemImage: item.icon)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Group {
                    switch section.wrappedValue {
                    case .overview:
                        OverviewView(device: device)
                    case .apps:
                        AppsView(device: device)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(26)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(device.name)
        .navigationSubtitle(device.modelName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await manager.reloadSelectedDevice() }
                } label: {
                    if manager.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(L("Обновить"), systemImage: "arrow.clockwise")
                    }
                }
                .help(Text(L("Перечитать сведения об устройстве")))
                .disabled(manager.isRefreshing)
            }
        }
    }
}
