import Foundation
import Combine

enum AppInstallState: Equatable {
    case idle
    case installing(InstallProgress)
    case success
    case failed(String)
}

final class DeviceManager: ObservableObject {
    @Published private(set) var devices: [Device] = []
    @Published var selectedDeviceID: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var statusMessage: String?

    @Published private(set) var pairingStates: [String: PairingStatus] = [:]
    @Published private(set) var apps: [String: [InstalledApp]] = [:]
    @Published private(set) var appsLoading: Set<String> = []
    @Published private(set) var appsErrors: [String: String] = [:]
    @Published private(set) var installStates: [String: AppInstallState] = [:] // Ключ: путь к ipa

    private var pollTask: Task<Void, Never>?
    private var infoCache: [String: DeviceInfo] = [:]

    init() {
        startPolling()
    }

    deinit {
        pollTask?.cancel()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    @MainActor
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let muxDevices = try await Task.detached(priority: .utility) {
                try USBMuxClient.listDevices()
            }.value

            var updated: [Device] = []
            updated.reserveCapacity(muxDevices.count)

            for mux in muxDevices {
                let key = mux.serialNumber.isEmpty ? "mux-\(mux.deviceID)" : mux.serialNumber

                var info = infoCache[key]
                if info == nil {
                    info = await Task.detached(priority: .utility) {
                        try? LockdownClient.fetchInfo(deviceID: mux.deviceID)
                    }.value
                }
                // Нативный lockdownd может быть недоступен (usbmuxd отклоняет
                // Connect). В этом случае читаем сведения через MobileDevice.
                if info == nil, !mux.serialNumber.isEmpty {
                    info = await Task.detached(priority: .utility) {
                        try? MobileDeviceBridge.shared.deviceInfo(identifier: mux.serialNumber)
                    }.value
                }
                if let info {
                    infoCache[key] = info
                }

                updated.append(Device(mux: mux, info: info, key: key))
            }

            devices = updated
            statusMessage = updated.isEmpty ? L("Устройства не найдены") : nil
            lastUpdated = Date()

            for device in updated where pairingStates[device.id] == nil {
                Task { [weak self] in
                    await self?.checkPairingStatus(for: device)
                }
            }

            let virtualSections: Set<String> = ["appstore", "downloads"]
            if let selected = selectedDeviceID,
               !virtualSections.contains(selected),
               !updated.contains(where: { $0.id == selected }) {
                selectedDeviceID = updated.first?.id
            } else if selectedDeviceID == nil {
                selectedDeviceID = updated.first?.id
            }
        } catch {
            statusMessage = error.localizedDescription
            lastUpdated = Date()
        }
    }

    /// Сбрасывает кеш сведений lockdownd и перечитывает данные.
    @MainActor
    func reloadSelectedDevice() async {
        if let selected = selectedDeviceID {
            infoCache.removeValue(forKey: selected)
            pairingStates.removeValue(forKey: selected)
            apps.removeValue(forKey: selected)
            appsErrors.removeValue(forKey: selected)
        }
        await refresh()
    }

    // MARK: - Pairing

    @MainActor
    func checkPairingStatus(for device: Device) async {
        guard pairingStates[device.id] == nil else { return }
        pairingStates[device.id] = .checking

        let identifier = device.udid
        let status = await Task.detached(priority: .utility) {
            MobileDeviceBridge.shared.pairingStatus(identifier: identifier)
        }.value

        pairingStates[device.id] = status
    }

    @MainActor
    func pair(device: Device) async {
        guard pairingStates[device.id] != .pairing else { return }
        pairingStates[device.id] = .pairing

        let identifier = device.udid
        do {
            try await Task.detached(priority: .userInitiated) {
                try MobileDeviceBridge.shared.pair(identifier: identifier)
            }.value

            pairingStates[device.id] = .paired
            infoCache.removeValue(forKey: device.id)
            apps.removeValue(forKey: device.id)
            appsErrors.removeValue(forKey: device.id)

            await refresh()
            await loadApps(for: device, force: true)
        } catch {
            pairingStates[device.id] = .failed(error.localizedDescription)
        }
    }

    // MARK: - Приложения

    @MainActor
    func loadApps(for device: Device, force: Bool = false) async {
        guard !appsLoading.contains(device.id) else { return }
        if !force, apps[device.id] != nil { return }

        appsLoading.insert(device.id)
        appsErrors.removeValue(forKey: device.id)
        defer { appsLoading.remove(device.id) }

        let identifier = device.udid
        do {
            let list = try await Task.detached(priority: .userInitiated) {
                try MobileDeviceBridge.shared.installedApps(identifier: identifier)
            }.value
            apps[device.id] = list
        } catch {
            appsErrors[device.id] = error.localizedDescription
        }
    }

    func pairingState(for deviceID: String) -> PairingStatus {
        pairingStates[deviceID] ?? .unknown
    }

    func installedApps(for deviceID: String) -> [InstalledApp] {
        apps[deviceID] ?? []
    }

    func isLoadingApps(for deviceID: String) -> Bool {
        appsLoading.contains(deviceID)
    }

    func appsError(for deviceID: String) -> String? {
        appsErrors[deviceID]
    }

    // MARK: - Установка .ipa

    func installState(for ipaPath: String) -> AppInstallState {
        installStates[ipaPath] ?? .idle
    }

    func isInstalling(on deviceID: String) -> Bool {
        installStates.values.contains { state in
            if case .installing = state { return true }
            return false
        }
    }

    func resetInstallStates() {
        installStates.removeAll()
    }

    @MainActor
    func installIPAs(device: Device, ipas: [IPAInfo]) async {
        for ipa in ipas {
            let currentState = installState(for: ipa.path)
            if case .installing = currentState { continue }
            if case .success = currentState { continue }

            await installApp(device: device, ipa: ipa)
        }
    }

    @MainActor
    func installApp(device: Device, ipa: IPAInfo) async {
        guard ipa.canInstall else {
            installStates[ipa.path] = .failed(ipa.blockingIssue ?? L("Установка этого пакета невозможна."))
            return
        }

        let ipaPath = ipa.path
        let identifier = device.udid
        let packageType = ipa.packageType

        installStates[ipaPath] = .installing(
            InstallProgress(phase: .transferring, percent: 0, status: "CopyingFile")
        )

        do {
            try await Task.detached(priority: .userInitiated) {
                try MobileDeviceBridge.shared.installApp(
                    identifier: identifier,
                    ipaPath: ipaPath,
                    packageType: packageType,
                    progress: { progress in
                        Task { @MainActor [weak self] in
                            self?.installStates[ipaPath] = .installing(progress)
                        }
                    }
                )
            }.value

            installStates[ipaPath] = .success
            await loadApps(for: device, force: true)
        } catch {
            installStates[ipaPath] = .failed(error.localizedDescription)
        }
    }

    @MainActor
    func uninstallApp(device: Device, app: InstalledApp) async {
        let deviceID = device.id
        let identifier = device.udid
        let bundleID = app.bundleID

        do {
            try await Task.detached(priority: .userInitiated) {
                try MobileDeviceBridge.shared.uninstallApp(identifier: identifier, bundleID: bundleID)
            }.value

            await loadApps(for: device, force: true)
        } catch {
            appsErrors[deviceID] = L("Ошибка удаления %@: %@", app.name, error.localizedDescription)
        }
    }
}
