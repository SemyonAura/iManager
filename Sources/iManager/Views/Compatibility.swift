import SwiftUI

extension View {
    @ViewBuilder
    func compatibleOnChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        // Use the old single-parameter closure form, available on macOS 11+.
        self.onChange(of: value, perform: action)
    }

    @ViewBuilder
    func compatibleTextSelection() -> some View {
        if #available(macOS 12.0, *) {
            self.textSelection(.enabled)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleTask(_ action: @escaping () async -> Void) -> some View {
        if #available(macOS 12.0, *) {
            self.task { await action() }
        } else {
            self.onAppear { Task { await action() } }
        }
    }
}

enum CompatButtonStyle {
    case prominent
    case bordered
    case borderless
    case plain

    @ViewBuilder
    func apply<V: View>(to view: V) -> some View {
        switch self {
        case .prominent:
            if #available(macOS 12.0, *) {
                view.buttonStyle(.borderedProminent)
            } else {
                view.buttonStyle(DefaultButtonStyle())
            }
        case .bordered:
            if #available(macOS 12.0, *) {
                view.buttonStyle(.bordered)
            } else {
                view.buttonStyle(DefaultButtonStyle())
            }
        case .borderless:
            view.buttonStyle(BorderlessButtonStyle())
        case .plain:
            view.buttonStyle(PlainButtonStyle())
        }
    }
}

extension Button {
    @ViewBuilder
    func compatButtonStyle(_ style: CompatButtonStyle) -> some View {
        style.apply(to: self)
    }
}

extension View {
    @ViewBuilder
    func compatButtonStyle(_ style: CompatButtonStyle) -> some View {
        style.apply(to: self)
    }
}

extension View {
    @ViewBuilder
    func compatForeground(_ color: Color) -> some View {
        if #available(macOS 12.0, *) {
            self.foregroundStyle(color)
        } else {
            self.foregroundColor(color)
        }
    }
}
