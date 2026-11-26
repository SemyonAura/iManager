import SwiftUI
import AppKit

/// Глобальное состояние окна настроек: его открывают и кнопка на панели
/// инструментов, и пункт меню приложения.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var isPresented = false

    private init() {}

    func present() {
        isPresented = true
    }
}

struct SettingsView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @Environment(\.presentationMode) private var presentationMode
    private func dismiss() { presentationMode.wrappedValue.dismiss() }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 470, height: 430)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22, weight: .medium))
                    .compatForeground(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L("Настройки"))
                    .font(.title3.weight(.semibold))
                Text(L("Настройки приложения"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Язык интерфейса"))
                        .font(.callout.weight(.semibold))
                    Text(L("Выберите язык интерфейса. Изменения применяются сразу."))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        ForEach(AppLanguage.allCases) { language in
                            languageRow(language)
                        }
                    }
                    .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("О приложении"))
                        .font(.callout.weight(.semibold))

                    HStack(spacing: 10) {
                        Image(systemName: "iphone.gen3")
                            .font(.title3)
                            .compatForeground(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iManager \(version) (\(build))")
                                .font(.caption.weight(.medium))
                            Text(L("iManager — менеджер iOS-устройств"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                }
            }
            .padding(20)
        }
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        let isSelected = l10n.language == language

        return Button {
            l10n.language = language
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Text(language == .ru ? "RU" : "EN")
                        .font(.caption.weight(.bold))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.title)
                        .font(.callout.weight(.medium))
                        .foregroundColor(.primary)
                    Text(language.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundColor(isSelected ? .accentColor : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .compatButtonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L("Закрыть")) {
                dismiss()
            }
            .compatButtonStyle(.prominent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}
