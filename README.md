# noto

当前只维护 PC（macOS）客户端和本地 CLI。一个原生 macOS 小记与待办应用。一个输入入口，本地保存；需要时交给已安装的 AI CLI 整理。

## 项目架构

SwiftPM 多 target，依赖方向单向：`NotoCore ← NotoSync ← NotoApp`、`NotoCore ← NotoCLI`，无反向依赖。

- **NotoCore**：数据模型（`Models.swift`）、SQLite 持久化与业务操作（`Store` 按域拆为 Timeline / Conversation / Mutation 三个扩展，搜索走 trigram FTS）、同步落库/outbox（`SyncStore.swift`）、AI CLI 调用（`Agent.swift`）、统一日志（`NotoLog.swift`）。不含 UI 与网络传输。
- **NotoSync**：同步传输层——Supabase 认证、PowerSync 副本、自适应轮询与冲突处理（登录态下有待传 2s / 空闲 15s / 失败指数退避）。落库都在 NotoCore，因此 CLI 不依赖本模块。
- **NotoApp**：macOS 主应用，按目录分层——`App/`（AppModel 按域拆分 + `TextDrafts` 输入草稿，逐键文本不触发整树刷新）、`Views/`（主窗口三视图与行组件）、`Input/`（NSTextView 桥与搜索框）、`Design/`（设计令牌与玻璃材质）、`Pill/`（屏幕边缘药丸，四边几何由 `PillEdge.contentTransform` 统一映射）。
- **NotoCLI**：`noto` 命令（ArgumentParser），与 App 共享同一个 Store；账号库指针 `active-account.json` 的路径常量收口在 `Store.activeAccountPointer`，由 NotoSync 写入。
- **backend/**：Supabase 迁移、PowerSync sync-rules、本地开发栈与契约测试。

脚本统一在 `scripts/`（构建、打包、QA 验证）；设计规约在 `design/`。日志统一走 `os.Logger`（subsystem `noto`，category `sync` / `agent`），UI 层不打日志，CLI 的 print 是 JSON 契约。

## AI 工作目录

正式数据保留在 Application Support；所有 AI 工具统一使用 Caches 下的 Noto 专用会话目录，按资料空间与会话隔离，上下文快照可重建；每轮运行文件使用系统临时目录并清理。详见 [AI 工作目录](design/AI-WORKSPACE.md)。

## 项目设计规约

[完整设计规约](design/DESIGN-SPEC.md) 是当前 macOS 界面的统一入口，覆盖全部页面、布局尺寸、字体与材质、图标、按钮、输入、动效、快捷键及验收要求。[端到端交互规范](design/E2E-UX.md) 定义三种视图与对话、最近删除的行为契约。

## 桌面端任务同步

桌面端保留 Supabase + PowerSync 任务同步，支持离线写入、账号隔离、冲突保留与任务删除恢复；记录和 AI 对话仍保存在当前设备。登录后可明确导入历史任务。

## 屏幕边缘的待办药丸

macOS 版有一枚吸附在屏幕边缘的贴边面板：平时只是贴边的一小块，鼠标悬停即展开「今日待办」进度环、「写一笔」和设置入口，再悬停到具体元素会弹出带箭头的描述卡（今日到期与逾期、操作说明）。点击环在看板查看，点击「写一笔」唤起主窗口录入。药丸悬浮于所有窗口之上、不抢焦点，全屏应用在前台时自动收起。右键菜单可换边或隐藏；按住 ⌥ 拖动可沿边缘移动，拖到别的屏幕边即换边；「设置 → 屏幕边缘」可悬停/常驻/隐藏、选择四条边与通透/纯黑材质，并可恢复居中。收起命中区沿边方向不变、进深方向加宽，玻璃表面按系统原生大面积采样再裁剪绘制，旧系统与降低透明度时回退纯黑。组件预览：`build/Noto.app --args --preview-pill`。贴边窗口机制改编自 [codenotch](https://github.com/vinzdg/codenotch)（MIT License，© vinzdg，见 THIRD-PARTY-NOTICES/codenotch.txt）。**药丸是核心功能，架构承诺见 [ADR-0001](docs/adr/0001-pill-is-core-feature.md)。**

## 下载与安装

在 [GitHub Releases](https://github.com/indie-builder/noto/releases) 下载 DMG，打开后把 Noto 拖到 Applications。Apple 芯片选 arm64，Intel 选 x86_64。当前预览版标有 `unnotarized`，尚未 Apple 公证，系统可能阻止打开。正式签名与自动发布配置见 [发布说明](RELEASE.md)。

## 从源码运行

需要 macOS 14+、Xcode/Swift 6 工具链。

```sh
zsh scripts/build.sh
open build/Noto.app
```

默认以记录列表为主体。双击阅读区空白处就近打开输入框，或用 ⌘N 在顶部唤起。回车换行，⌘ 回车直接保存笔记；“询问 AI”是独立的次级入口。Esc 或点击外部收起输入框，进程内草稿保留；再次双击只移动同一个输入框。AI 运行时可以继续保存笔记。

双击记录正文原位编辑，⌘ 回车或“保存”提交，Esc 或“取消”放弃。未保存修改会阻止切换到其他记录或新建。待办沿用原生日期控件；带对话的记录只修改列表文字，历史问答不变。打开历史对话统一点击记录上的“对话”按钮。

⌘K 搜索，⌘, 设置 AI CLI，⌘⇧ 回车添加待办（输入框打开时）。⌘Z 撤销文本、⌘⌥Z 重做文本、⌘⇧Z 撤销记录操作。操作反馈固定在阅读区底部，保存冲突保留草稿。宽度不足 980pt 时对话切为单栏；⌘N 返回记录并打开输入，顶栏对话按钮可返回当前对话。

## 任务看板与月历

顶栏的单个视图图标打开原生菜单，切换笔记、看板和日历（⌘1 / ⌘2 / ⌘3），并记住选择。笔记保留时间线；任务看板汇总全部历史任务，按「待开始 / 进行中 / 已完成」分列。星标表示重要，支持「只看重要」与全文/对话搜索组合筛选；切换模式清空搜索。

拖拽卡片到另一列，或用卡片菜单改变状态。点击卡片编辑文字、状态、重要标记和截止日期；⌘↵ 保存、Esc 取消。任务模式的 ⌘N 打开新建任务，前两列的 ＋ 默认使用该列状态。新建草稿取消后在进程内保留，编辑冲突不会覆盖 CLI 的修改。笔记右键「转为任务」保留原 ID、文字和对话，并提供撤销与「在看板查看」。

未完成列按重要优先、截止日期（无日期最后）、创建时间排序。已完成列按完成时间排序，先显示 20 条，可加载更多；修改文字不会重排完成时间。窄窗口可横向滚动看板，列宽至少 260pt。日期只记录到天，不产生定时提醒。

```sh
build/bin/noto todo add --title '梳理交互' --status pending --priority important --request-id unique-key --json
build/bin/noto todo update --id FULL_ID --status in_progress --json
build/bin/noto todo list --status open --priority important --json
build/bin/noto note convert-to-todo --id FULL_ID --json
```

状态字段：`pending / in_progress / completed`；优先级：`normal / important`。省略创建属性时默认待开始、普通。`todo update` 只修改显式提供的字段；`--clear-due` 清除日期。旧的 `complete/reopen` 命令继续可用，`list --status open` 包括待开始与进行中；重新打开回到待开始。JSON 保留 `completed`，并返回新属性和已完成任务的 `completedAt`。旧任务自动迁移为普通优先级，旧完成时间用历史更新时间近似回填。应用与 CLI 应一起使用本次构建。

月历按截止日期展示同一批任务，周一开始、固定六周。紧凑日期格只显示未完成数量或完成提示，点击日期只更新下方列表、不滚走月历；收纳盒包含所有没有日期的任务（含已完成）。已完成任务仍留在原截止日期。左右箭头切月，定位图标回到今天；当天列表使用简洁任务行，不重复日期；已完成默认折叠。搜索直接展示跨日期结果，清空后恢复选中日期。日历中 ⌘N 使用选中日期创建；在「未安排」中新建则不设日期。取消的新建草稿会保留已有字段。创建时只突出文字，日期入口支持今天、明天、选择日期及清除，星标可选；状态在编辑时设置。

日历拖动仅改变日期，看板拖动仅改变状态；均使用拖动开始时的快照检查冲突，并支持撤销。CLI 与 AI 无需新接口：`todo update --id ID --due 2026-09-11` 将任务放到该日期，`--clear-due` 移到「未安排」。日期采用本地日历语义，不按 UTC 转换。

## 本地 CLI 和 Skill

```sh
build/bin/noto note add --text '今天想清楚了产品方向。' --json
build/bin/noto todo add --title '整理草图' --due 2026-09-09 --json
build/bin/noto todo list --status open --json
build/bin/noto search '草图' --json
build/bin/noto todo complete --id FULL_ID --json
build/bin/noto conversation --id FULL_ID --json
build/bin/noto export --include-conversations --json
build/bin/noto doctor
```

命令返回 JSON，失败返回非零退出码。`--request-id` 支持创建重试去重。可将 `build/bin` 加入 PATH；`Skills/noto/SKILL.md` 是可安装到所用 Agent 的技能包。Skill 不等于云端到本机的连接：ChatGPT 云端写入仍需后续 MCP/隧道接入。

应用与 CLI 共享 `~/Library/Application Support/Noto/notes.sqlite`。界面每 1.5 秒读取变更。测试可用 `NOTO_DATABASE` 或 CLI 的 `--database` 指定隔离数据库。数据库迁移由 GRDB 管理。备份建议使用 `export --include-conversations` 导出笔记及完整对话；不要在运行时只复制 SQLite 主文件而遗漏 WAL。

## AI

支持启动本机 Codex、Claude Code、OpenCode 和 Kimi CLI，使用各自的现有登录和默认模型。默认 OpenCode，设置中仅提供一个 AI CLI 选择项。首次使用请先在该 CLI 中完成登录。

首次提问自动保存为一条笔记；点击记录上的“对话”按钮重新打开完整对话并继续。每轮用户消息与 AI 回复独立保存，搜索会命中完整对话并返回所属记录。对话输入回车换行，⌘ 回车发送；失败可重试，停止会保留已保存的消息。修改列表文字不会改写原问题或历史回复。

每轮问题下的「执行过程」默认收起，点击查看上下文读取数量、实际 CLI 启动与返回、回复保存结果及耗时。失败信息也会保存。这里显示应用的实际执行状态，不包含模型内部推理文本。

输入、此前对话和明确选择的内容范围会提供给设置里选定的 CLI。默认仅当前记录，每轮读取最新版本；也可选择当前视图已载入的记录（搜索时为已载入的匹配结果），范围与数量显示在对话输入区。AI 返回结构化意图，Noto 校验后在同一事务中执行，失败不做部分修改。AI 运行期间的外部修改会阻止覆盖。超时 150 秒，支持取消，错误时保留输入。不会使用假回复代替真实 AI。

持续对话由 Noto 保存和重放历史：每轮调用 CLI 的非交互接口，不依赖 CLI 自己的 session ID，因此重启应用后仍可继续。回复完成后显示，不逐 token 流式输出；保存的是用户和 AI 可见消息，不包括 CLI 内部推理或工具日志。历史不会静默截断，达到输入容量后会提示开启新对话。不提供终端 TUI 或 CLI 原生工具审批流。CLI 各版本可能改变参数，需要按安装版本核实。到期日目前精确到天，不会在指定时间弹出提醒。

`noto ask '明天整理草图' --provider codex` 只生成建议；加 `--apply` 才写入。AI 工具已有此 Skill 时应直接调用数据命令，无需再嵌套调用 ask。

## 验证

```sh
swift test
python3 scripts/verify-cli.py
```

回归检查用 `verify-cli.py`；长历史测试数据用 `python3 scripts/seed-design-fixture.py /tmp/noto-new-fixture.sqlite`（拒绝覆盖已有数据库）。

SwiftUI + AppKit / GRDB + SQLite / Swift Argument Parser。构建脚本生成本机 ad-hoc 签名的应用，不是已公证的公开发行包。
