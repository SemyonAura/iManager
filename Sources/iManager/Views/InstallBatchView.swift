import SwiftUI

struct InstallBatchView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let device: Device
    let ipas: [IPAInfo]

    @EnvironmentObject private var manager: DeviceManager
    @Environment(\.presentationMode) private var presentationMode

    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }

    private var isAnyInstalling: Bool {
        manager.isInstalling(on: device.id)
    }

    private var allDone: Bool {
        ipas.allSatisfy { ipa in
            let state = manager.installState(for: ipa.path)
            if case .success = state { return true }
            if case .failed = state { return true }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(22)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(ipas) { ipa in
                        ipaRow(ipa)
                        if ipa.id != ipas.last?.id {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            actions
                .padding(18)
        }
        .frame(width: 600, height: 480)
        .interactiveDismissDisabled(isAnyInstalling)
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "square.stack.3d.down.right.fill")
                    .font(.title2)
                    .compatForeground(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L("Установка приложений"))
                    .font(.headline)
                Text(L("Выбрано: %d файлов .ipa", ipas.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }

    private func ipaRow(_ ipa: IPAInfo) -> some View {
        let state = manager.installState(for: ipa.path)
        
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: "arrow.down.app")
                    .font(.subheadline)
                    .compatForeground(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(ipa.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(ipa.bundleID) • \(ByteFormatter.string(ipa.fileSize))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            statusView(for: state, ipa: ipa)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func statusView(for state: AppInstallState, ipa: IPAInfo) -> some View {
        switch state {
        case .idle:
            if let issue = ipa.blockingIssue {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .help(issue)
            } else {
                Text(L("В очереди"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        case .installing(let progress):
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(progress.localizedStatus)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    ProgressView(value: Double(progress.percent) / 100.0)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                }
                Text("\(progress.percent)%")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

        case .failed(let message):
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .help(message)
        }
    }

    private var actions: some View {
        HStack {
            if allDone {
                Spacer()
                Button(L("Готово")) {
                    dismiss()
                }
                .compatButtonStyle(.prominent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(L("Отмена")) {
                    dismiss()
                }
                .disabled(isAnyInstalling)

                Spacer()

                if isAnyInstalling {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                    Text(L("Установка в очереди…"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    Button {
                        Task { await manager.installIPAs(device: device, ipas: ipas) }
                    } label: {
                        Text(L("Установить все"))
                    }
                    .compatButtonStyle(.prominent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
