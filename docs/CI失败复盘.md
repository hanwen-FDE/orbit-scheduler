# Orbit CI 失败复盘（codex/test 分支 · 2026-09-12 至 09-13）

本文档汇总本项目开发过程中 **5 次推送 CI 构建失败**的完整原因、修复过程与经验教训，
作为后续提交的质量检查基线。

---

## 一、失败总览

| # | 失败提交 | 时间 (UTC) | 根因分类 | 修复提交 |
|---|---------|-----------|---------|---------|
| 1 | `395393b` | 09-12 21:34 | 缺少 import | `80057ce` |
| 2 | `80057ce` | 09-12 21:52 | 声明与调用形式不一致（变量 vs 函数） | `f9443dd` |
| 3 | `a9a8f6c` | 09-12 22:16 | 同文件函数重复声明（删漏一半） | `7de57ba`（仍未修完）→ `7f9ad93` |
| 4 | `7de57ba` | 09-12 22:2x | 同上：`enableDailyNotifications` 仍重复 | `7f9ad93` |
| 5 | `c9fd765` | 09-13 00:0x | 三处 Swift 语义错误（协议签名/参数顺序/keypath） | `ebe6ec3` |

两次连续失败（#3→#4）源于**同一个修复只改了一半**，是本复盘最重要的一条教训。

---

## 二、逐次详情

### 失败 1 — `395393b`（11 项交互重构）

**报错**（xcodebuild）：

```
Models.swift:35: error: cannot find type 'Color' in scope   （及 52、47 行同类）
ChatView.swift:188 / SideDrawerView.swift:103 / ScheduleListView.swift:84:
    error: the compiler is unable to type-check this expression in reasonable time
```

**根因**：`Models.swift` 原本只有 `import Foundation`。本次新增的 `OrbitThemePreset`
枚举使用了 `Color`，没有补 `import SwiftUI`。`Color` 类型缺失进一步导致依赖它的
复杂 SwiftUI 表达式类型推断爆炸，产生 5 条"type-check timeout"**误导性报错**。

**修复**（`80057ce`，+1 行）：`import Foundation` 下补 `import SwiftUI`。

**教训**：
- 给纯 Foundation 的模型文件加 UI 类型时，第一件事检查 import；
- "type-check in reasonable time" 报错**经常是连锁反应**，先找 `cannot find type`
  这类根因报错，超时报错先搁置。

---

### 失败 2 — `80057ce`（修复 1 的提交本身失败）

**报错**（16 处同类）：

```
MessageViews.swift:63: error: cannot call value of non-function type 'Color'
ScheduleAssistantApp.swift:44: error: cannot call value of non-function type 'Color'
（另有多处 type-check timeout 连锁）
```

**根因**：主题色入口声明成了**计算属性** `var orbitAccent: Color`，但全项目 40 处
调用全部写成函数形式 `orbitAccent()`。属性被当函数调用直接报错，并再次引发
连锁类型推断超时。

**修复**（`f9443dd`，1 行）：`var orbitAccent: Color {…}` → `func orbitAccent() -> Color {…}`。

**教训**：
- 引入全局 API 时，**先定死它的调用形式**（函数加括号），再批量生成调用点；
- 修复提交推送后同样必须轮询 CI——本次修复提交自己就挂了，如果只看上一轮
  会漏掉。

---

### 失败 3 + 4 — `a9a8f6c` / `7de57ba`（抽屉重组，连续两次）

**报错**：

```
失败3: SideDrawerView.swift:198: error: invalid redeclaration of 'timeText'
       SideDrawerView.swift:202: error: invalid redeclaration of 'enableDailyNotifications()'
失败4: SideDrawerView.swift:198: error: invalid redeclaration of 'enableDailyNotifications()'
```

**根因**：用 Python 脚本按文本块替换重构抽屉时，新版"每日简报"区块自带
`timeText` / `enableDailyNotifications` 两个辅助函数，而旧版同区块的这两个函数
没有被一起删掉，形成**同 struct 内的重复声明**。

失败 3 的修复（`7de57ba`）只按"第二个 `timeText` 起点"做区间删除，删完
`timeText` 的闭包就停了，**把紧随其后的第二个 `enableDailyNotifications` 留在了
文件里**——导致失败 4。失败 4 的修复（`7f9ad93`）按函数签名定位 + 大括号配平
删除了完整的第二个函数，才真正通过。

**教训**（本项目最严重的一类问题）：
- 文本块删除必须**按声明签名定位、按括号配平删到函数闭合**，禁止"删到某个
  标记就停"；
- 涉及"替换整个区块"的补丁，写盘前必须对**同名声明计数**（见第四节检查项）；
- 修复重复声明的提交，要确认**所有同名符号**只剩一份，而不是只看报错第一条。

---

### 失败 5 — `c9fd765`（v4.2 十四项）

**报错**（三处独立错误）：

```
ChatView.swift:273: error: type 'ChatView.EdgeSwipeBack' does not conform to protocol 'ViewModifier'
ChatView.swift:99:  error: argument 'onOpenToday' must precede argument 'message'
SideDrawerView.swift:119: error: key path value type 'EKCalendar' cannot be converted...
                     error: invalid component of Swift key path
```

**根因**：
1. `ViewModifier` 协议要求的方法签名是 `func body(content: Content)`，
   实现写成了 `func body(body: Content)`——参数名不匹配即视为未实现协议方法；
2. `MessageRow` 的成员声明顺序是 `onOpenToday` 在前，而调用点按
   `message: …, onTapCard: …, onOpenToday: …` 顺序传参——SwiftUI 的成员级
   参数顺序必须与声明一致（有默认值的参数也一样）；
3. 可见日历代码里写了 `calendars.map(\.$0.calendarIdentifier)`，
   keypath 中混入 `$0` 属于非法语法，正确写法是 `calendars.map { $0.calendarIdentifier }`。

**修复**（`ebe6ec3`，3 行）：签名改 `body(content:)`；成员顺序调换；
map 改闭包。

**教训**：
- 这三类错误（协议方法参数名、struct 成员初始化顺序、keypath 语法）都是
  **括号配平/引用扫描无法覆盖的语义级错误**，只能靠真编译暴露——本地没有
  Swift 工具链（Windows）时，第一轮 CI 失败某种意义上是流程的一部分，
  关键是失败后**一次性把日志里所有错误归类修完**，不许只修第一条。

---

## 三、根因归类

| 类别 | 次数 | 典型表现 |
|-----|-----|---------|
| 文本补丁副作用（重复声明/删漏/括号错位） | 2 | invalid redeclaration；多余 `}` 把子视图挤出容器 |
| Swift 语义错误（本地无法静态验证） | 2 | 协议签名、参数顺序、keypath、import 缺失 |
| 声明形式与调用形式不一致 | 1 | 属性 vs 函数调用 |
| 连锁误导报错（随根因消失） | 4/5 次伴随 | type-check timeout |

补充：另有多起同类问题（chatBubble 多括号、wakeTime/sleepTime 重复、
`\.$0` keypath、stale 符号残留）在**推送前的本地扫描**中被拦下，未进入 CI。
说明本地静态扫描有效，但覆盖不到语义层。

---

## 四、现行提交前检查清单

每次推送前依次执行，任何一步不过则不提交：

1. **括号配平**：全部 `.swift` 文件 `{}`、`()` 计数相等；
2. **残留符号扫描**：被重构/删除的旧符号名 grep 必须为 0 命中
   （例：`selectedTab`、`embeddedMode`、旧函数名）；
3. **成员级重复声明扫描**：脚本解析"类型栈 + 4 空格缩进成员"，同一类型内
   同名 `func/var/let` 只允许出现一次；
4. **新符号交叉引用**：新增类型/方法在使用文件中 grep 得到，声明文件唯一；
5. **推送后轮询 CI 到最终态**：`completed` 才算结束，失败立即拉日志
   （`actions/runs/{id}/logs`，需 token），**归类全部 error 后一次性修复**；
6. 修复提交重复第 5 步，直到 success 并确认 artifacts（ipa + app）生成。

---

## 五、后续可选改进

- 在 workflow 中加一个 **swiftlint / swift-format 快速失败 job**，把语法层
  问题在完整编译前 1-2 分钟内暴露；
- Windows 侧配置 Swift 工具链做本地 `swiftc -parse` 语法检查，把语义错误
  左移到提交前；
- 大批量重构改为"整文件重写"而非"文本块替换"，从源头消灭重复声明类问题。

---

*文档生成：2026-09-13，基于 codex/test 分支 `ebe6ec3` 为止的全部 CI 记录。*
