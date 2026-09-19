import SwiftUI

// Shared native tokens. Semantic colors follow macOS appearance and contrast.
enum NotoDesign {
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let field = Color.primary.opacity(0.045)
    static let body = Font.system(size: 15)
    static let caption = Font.system(size: 12)
    static let radius: CGFloat = 12
}

extension View {
    /// Fixed frame in one call.
    func frame(_ size: CGSize, alignment: Alignment = .center) -> some View {
        frame(width: size.width, height: size.height, alignment: alignment)
    }
}

extension String {
    /// 去掉首尾空白；「非空才可保存」类判断统一走这里。
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
}

/// 统一的行内错误提示；表单与面板共用。
struct ErrorLabel: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(NotoDesign.caption).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// Shared chrome for actions; native menus retain their keyboard behavior.

/// 按压缩放 + 悬停衬底 + 禁用降透明，是全部按钮样式的公共内核。
private struct PressFeedback: ViewModifier {
    var pressed: Bool
    var cornerRadius: CGFloat
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(NotoMotion.animation(.feedback), value: pressed)
            .background(enabled ? Color.primary.opacity(pressed ? 0.10 : hovering ? 0.055 : 0) : .clear,
                        in: RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovering = $0 }
            .animation(NotoMotion.hover, value: hovering)
            .opacity(enabled ? 1 : 0.4)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var prominent = false
    var icon = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PressFeedback(pressed: configuration.isPressed, cornerRadius: 6))
            .font(.system(size: 13, weight: .regular))
            .padding(.horizontal, icon ? 0 : 10)
            .frame(minWidth: 28, minHeight: 28)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Keep the hit rectangle fixed while the label responds to a press.
struct NavigationButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 40
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .modifier(PressFeedback(pressed: configuration.isPressed, cornerRadius: 7))
    }
}

extension View {
    func actionMenuStyle() -> some View {
        self.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .modifier(PressFeedback(pressed: false, cornerRadius: 6))
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
