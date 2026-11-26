import SwiftUI

struct FeaturePlaceholderView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let title: String
    let icon: String
    let summary: String
    let features: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .light))
                    .compatForeground(Color.accentColor)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.title3.weight(.semibold))
                        Text(L("В разработке"))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                            .foregroundColor(.orange)
                    }
                    Text(summary)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L("Запланировано"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                ForEach(features, id: \.self) { feature in
                    Label(feature, systemImage: "circle.dashed")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.underPageBackgroundColor))
        )
    }
}

struct EmptyStateView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 132, height: 132)
                Image(systemName: "iphone")
                    .font(.system(size: 58, weight: .light))
                    .compatForeground(Color.accentColor)
            }

            Text(L("Подключите iPhone или iPad"))
                .font(.title2.weight(.semibold))

            Text(L("iManager автоматически обнаружит устройство по USB или Wi-Fi, если на устройстве включена синхронизация по Wi-Fi."))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 430)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                Text(L("Работает напрямую через usbmuxd — без сторонних утилит"))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
