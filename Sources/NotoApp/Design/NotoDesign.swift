import SwiftUI

// Shared native tokens. Semantic colors follow macOS appearance and contrast.
enum NotoDesign {
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let field = Color.primary.opacity(0.045)
    static let body = Font.system(size: 15)
    static let caption = Font.system(size: 12)
    static let radius: CGFloat = 12
}

// Shared chrome for actions; native menus retain their keyboard behavior.
struct QuietButtonStyle: ButtonStyle {
    var prominent = false
    var icon = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(NotoMotion.animation(.feedback), value: configuration.isPressed)
            .font(.system(size: 13, weight: .regular))
            .padding(.horizontal, icon ? 0 : 10)
            .frame(minWidth: 28, minHeight: 28)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .modifier(ActionSurface(pressed: configuration.isPressed))
            .opacity(enabled ? 1 : 0.4)
    }
}

private struct ActionSurface: ViewModifier {
    var pressed = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(enabled ? Color.primary.opacity(pressed ? 0.10 : (hovering ? 0.055 : 0)) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
            .animation(NotoMotion.hover, value: hovering)
    }
}

extension View {
    func actionMenuStyle() -> some View {
        self.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .modifier(ActionSurface())
    }
}

struct ActionIcon: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        Image(systemName: name).font(.system(size: 13, weight: .regular))
            .frame(width: 28, height: 28)
    }
}

/// 图标按钮的统一形态：帮助与无障碍标签共用一份文案。
struct QuietIconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    init(_ icon: String, help: String, action: @escaping () -> Void) {
        self.icon = icon; self.help = help; self.action = action
    }
    var body: some View {
        Button(action: action) { ActionIcon(icon) }
            .buttonStyle(QuietButtonStyle(icon: true)).help(help).accessibilityLabel(help)
    }
}

/// 关闭脏编辑器前的确认弹窗；行内编辑与任务编辑共用。
struct UnsavedChangesAlert: ViewModifier {
    @Binding var isPresented: Bool
    var title = "保存修改？"
    let canSave: Bool
    let save: () -> Void
    let discard: () -> Void
    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button("保存") { save() }.disabled(!canSave)
            Button("放弃修改", role: .destructive) { discard() }
            Button("继续编辑", role: .cancel) { }
        } message: { Text("关闭前可以保存修改，或继续编辑。") }
    }
}

extension View {
    func unsavedChangesAlert(isPresented: Binding<Bool>, title: String = "保存修改？", canSave: Bool, save: @escaping () -> Void, discard: @escaping () -> Void) -> some View {
        modifier(UnsavedChangesAlert(isPresented: isPresented, title: title, canSave: canSave, save: save, discard: discard))
    }
}
