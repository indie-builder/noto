import SwiftUI
import AppKit
import NotoCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var showDeleted = false
    @State private var toolLocated: String?
    @State private var toolChecked = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("完成") { model.settings = false }
                    .help("关闭设置").accessibilityLabel("关闭设置")

            }.padding(.horizontal, 40).padding(.vertical, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsGroup {
                        settingsRow("AI 工具") {
                            Picker("AI 工具", selection: $model.provider) {
                                ForEach(Provider.allCases) { provider in
                                    Label { Text(provider.title) } icon: { Image(nsImage: provider.settingsIcon) }.tag(provider)
                                }
                            }.labelsHidden().pickerStyle(.menu)
                                .help("下一次请求生效，正在执行的请求不受影响。")
                        }
                        // 安装状态在选择时即可见，而不是等到第一次提问才失败。
                        if toolChecked {
                            if let toolLocated {
                                Label {
                                    Text("已找到：\(toolLocated)").lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                } icon: {
                                    Image(systemName: "checkmark.circle")
                                }.font(NotoDesign.caption).foregroundStyle(.secondary)
                            } else {
                                Label("未找到 \(model.provider.title)，请先安装并在其中完成登录", systemImage: "exclamationmark.circle")
                                    .font(NotoDesign.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    VStack(spacing: 4) {
                        Button { showDeleted = true } label: {
                            HStack(spacing: 10) {
                                Text("最近删除").font(.system(size: 13, weight: .medium))
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                            }.padding(.horizontal, 10).frame(height: 40).contentShape(Rectangle())
                        }.buttonStyle(NavigationButtonStyle()).accessibilityLabel("查看最近删除")
                    }.padding(6).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
        }.frame(width: 480, height: 460).background(NotoGlassSurface(radius: 20)).buttonStyle(QuietButtonStyle())
            .sheet(isPresented: $showDeleted) { RecentlyDeletedView(model: model).presentationBackground(.clear) }

            .onExitCommand { model.settings = false }
            .task(id: model.provider) { refreshToolPath() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshToolPath() }
    }
    /// 与对话页同一套重检时机：切换工具或应用回到前台时重新定位。
    private func refreshToolPath() {
        toolLocated = model.provider.locate()
        toolChecked = true
    }

    /// 标签在左、控件靠右对齐的一行；控件统一宽度让设置页两列对齐。
    private func settingsRow<Content: View>(_ label: String, @ViewBuilder control: () -> Content) -> some View {
        HStack {
            Text(label)
            Spacer()
            control().fixedSize().frame(width: 216, alignment: .trailing)
        }.frame(minHeight: 36)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
    }
}

extension Provider {
    /// 图标只解码一次：设置面板每次重渲染不再同步读盘。
    private static let iconCache: [String: NSImage] = {
        var icons: [String: NSImage] = [:]
        for provider in Provider.allCases {
            guard let url = Bundle.module.url(forResource: provider.rawValue, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { continue }
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            icons[provider.rawValue] = image
        }
        return icons
    }()

    var settingsIcon: NSImage { Self.iconCache[rawValue] ?? NSImage() }
}
