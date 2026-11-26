import SwiftUI

struct DeviceHeader: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let device: Device

    @EnvironmentObject private var manager: DeviceManager

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.30), Color.accentColor.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: device.isTablet ? "ipad" : "iphone")
                    .font(.system(size: 46, weight: .light))
                    .compatForeground(Color.accentColor)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.15))
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(device.name)
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(1)

                Text(device.modelName)
                    .font(.title3)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    StatusBadge(
                        text: device.connection.title,
                        systemImage: device.connection.symbol,
                        tint: .accentColor
                    )
                    StatusBadge(
                        text: "iOS \(device.iosVersion)",
                        systemImage: "cpu",
                        tint: .secondary
                    )
                    switch manager.pairingState(for: device.id) {
                    case .paired:
                        StatusBadge(
                            text: L("Сопряжено"),
                            systemImage: "checkmark.shield",
                            tint: .green
                        )
                    case .notPaired:
                        StatusBadge(
                            text: L("Не сопряжено"),
                            systemImage: "lock.open",
                            tint: .orange
                        )
                    case .pairing:
                        StatusBadge(
                            text: L("Сопряжение…"),
                            systemImage: "arrow.triangle.2.circlepath",
                            tint: .accentColor
                        )
                    case .failed:
                        StatusBadge(
                            text: L("Ошибка pairing"),
                            systemImage: "exclamationmark.triangle",
                            tint: .red
                        )
                    case .checking, .unknown:
                        StatusBadge(
                            text: L("Проверка pairing"),
                            systemImage: "shield",
                            tint: .secondary
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

struct StatusBadge: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .compatForeground(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct InfoTile: View {
    let title: String
    let value: String
    let icon: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .compatForeground(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .compatibleTextSelection()
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}

struct NoticeCard: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(text)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.20))
        )
    }
}
