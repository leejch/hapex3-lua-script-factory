# HApex3 Lua Script Factory

一个用于持续创建、修改、整理和归档 HApex3.0 / HOOZi Lua 脚本的工厂型仓库。

本仓库不只是普通 Lua 脚本项目，而是一个可复用的**脚本资产工厂**：

* 每次新的 Codex 对话都可以创建一个新的 Lua 脚本。
* 已有 Lua 脚本可以被修改、分叉、改进或特化。
* 成品脚本会被当作可复用资产管理。
* 旧版本会被有意识地归档在仓库内，而不是只依赖 Git 历史回溯。
* 脚本会按照主要 HApex3.0 Lua API 模块或主要运行用途分类整理。

英文是本仓库文档的原生语言。
`README_CN.md` 是 `README.md` 的简体中文翻译版。

## AI 入口文件

本仓库设计用于 OpenAI Codex、Codex CLI、Claude Code、opencode、Aider 或其他 AI 编码助手。

主要 AI 指令文件包括：

```text
AGENTS.md
SKILL.md
```

使用方式如下：

| 文件             | 主要使用者                                                   | 用途                  |
| -------------- | ------------------------------------------------------- | ------------------- |
| `AGENTS.md`    | Codex / Codex CLI / opencode / Aider / 支持 AGENTS.md 的工具 | 主项目指令文件             |
| `SKILL.md`     | Claude Code                                             | 带有分发元数据的 skill 入口文件 |
| `README.md`    | 人类和 AI agent                                            | 仓库概览、资产工作流、目录规则     |
| `README_CN.md` | 人类和 AI agent                                            | `README.md` 的简体中文翻译 |

对于 Codex 云端使用场景，`AGENTS.md` 是最重要的指令文件。
Codex 在生成、编辑或移动 Lua 脚本之前，应先读取 `AGENTS.md`。

不要只根据 `README.md` 生成脚本。
`README.md` 解释仓库工作流；`AGENTS.md` 定义编码行为。

## 仓库核心用途

本仓库用于支持一个重复执行的工作流：

```text
新的 Codex 对话
        ↓
用户描述 Lua 脚本需求
        ↓
Codex 读取 AGENTS.md 和 references/
        ↓
Codex 创建或修改脚本
        ↓
脚本被保存到正确的工厂目录
        ↓
稳定脚本成为可复用资产
        ↓
旧版本或替代版本被归档，供未来复用
```

本仓库应保留有用的脚本历史，即使用户不想通过 Git commit 来回顾旧版本。

因此，归档目录是项目设计的一部分。
它不是 Git 的替代品，但它提供了一个更适合人工浏览的旧版本、替代版本和废弃版本脚本库。

## 推荐仓库结构

```text
hapex3-lua-script-factory/
├── README.md
├── README_CN.md
├── AGENTS.md
├── SKILL.md
├── CATALOG.md
├── references/
│   ├── api-reference.md
│   ├── guide.md
│   └── examples.md
├── scripts/
│   ├── _workbench/
│   ├── _templates/
│   ├── finished/
│   │   ├── event/
│   │   ├── gui/
│   │   ├── esp/
│   │   ├── net/
│   │   ├── game/
│   │   ├── draw/
│   │   ├── math/
│   │   ├── file/
│   │   ├── input/
│   │   ├── log/
│   │   ├── script/
│   │   ├── time/
│   │   ├── config/
│   │   ├── json/
│   │   └── mixed/
│   └── archive/
│       └── asset-name/
├── lib/
├── tests/
├── tools/
└── .gitignore
```

## 必需的顶层文件

### `AGENTS.md`

Codex 和其他支持 AGENTS.md 工具的主指令文件。

它应定义：

* HApex3.0 / HOOZi Lua 脚本上下文何时适用
* 如何使用参考文件
* API 调用约定
* 脚本生成规则
* 注释语言要求
* 目录放置规则
* 归档规则
* 验证预期

发生冲突时，`AGENTS.md` 优先级高于 `README.md`。

### `SKILL.md`

Claude Code 的 skill 入口文件。

它应包含与 `AGENTS.md` 相同的核心脚本约定，但格式应符合 Claude Code 预期的 skill 格式。

### `CATALOG.md`

脚本资产的人类可读索引。

该文件应列出重要脚本的用途、状态、模块分类、路径和最新已知验证状态。

建议列：

| Asset            | Category | Path                                                    | Status       | Notes    |
| ---------------- | -------- | ------------------------------------------------------- | ------------ | -------- |
| center-crosshair | draw     | `scripts/finished/draw/draw__center_crosshair__v01.lua` | stable       | 绘制屏幕中心准星 |
| damage-logger    | game     | `scripts/finished/game/game__damage_logger__v01.lua`    | experimental | 需要运行时验证  |

当新增、重命名、归档或提升一个成品脚本时，应更新 `CATALOG.md`。

## 参考文件

详细 HApex3.0 Lua 知识位于：

```text
references/
├── api-reference.md
├── guide.md
└── examples.md
```

这些文件应只在需要时读取。

| 任务                      | 应读取                              |
| ----------------------- | -------------------------------- |
| 查询 API 参数、返回值、字段或模块行为   | `references/api-reference.md`    |
| 查找完整可运行脚本示例             | `references/examples.md`         |
| 理解项目布局、生命周期、IPC、时序或常见陷阱 | `references/guide.md`            |
| 生成或编辑 Lua 脚本            | 先读 `AGENTS.md`，再读相关 reference 文件 |

不要把完整 API 参考复制进 README 文件。
大型参考资料应保留在 `references/` 中。

## 脚本工厂目录

### `scripts/_workbench/`

临时工作区。

该目录用于：

* Codex 任务过程中创建的草稿
* 未完成脚本
* 一次性测试版本
* 尚未准备好成为资产的脚本

如果一个脚本变得有用，不应长期停留在 `_workbench/`。
一旦脚本稳定，或值得作为资产保留，应移动到 `scripts/finished/<category>/`。

### `scripts/_templates/`

可复用脚本模板。

该目录用于存放骨架模板，例如：

* 基础 frame update 脚本
* GUI 控件脚本
* ESP 元素脚本
* notification 脚本
* HTTP callback 脚本
* config switching 脚本

模板不是成品资产。
模板是未来生成脚本的起点。

### `scripts/finished/`

成品脚本资产库。

该目录下的脚本被视为可复用资产。

成品脚本必须按照其主要 HApex3.0 Lua API 模块或主要运行用途分类。

必需模块分类目录：

```text
scripts/finished/
├── event/
├── gui/
├── esp/
├── net/
├── game/
├── draw/
├── math/
├── file/
├── input/
├── log/
├── script/
├── time/
├── config/
├── json/
└── mixed/
```

### `scripts/archive/`

旧脚本、替代版本、被替换脚本或废弃脚本的人类可读归档库。

归档目录存在的原因是：并非所有有用的旧脚本都应该只通过 Git 历史恢复。

归档适用于：

* 大改前的旧版本
* 不同需求下的替代版本
* 已被替换但仍可能有用的脚本
* 可作为参考材料的旧脚本
* 未来可能基于其分叉出新版本的脚本

推荐归档结构：

```text
scripts/archive/
└── 2026-06/
    └── center-crosshair/
        ├── 20260610-1430__before_gui_options_added__draw__center_crosshair__v01.lua
        └── NOTES.md
```

每个归档脚本都应保留足够上下文，以便理解它为什么被归档。

如果原因不明显，建议添加一个小型 `NOTES.md`。

## 成品脚本分类规则

每个成品脚本应放在最能描述其主要用途的目录下。

| 分类        | 适用于主要关注                           |
| --------- | --------------------------------- |
| `event/`  | 事件订阅、自定义事件总线、事件驱动协调               |
| `gui/`    | 菜单控件、UI 分组、用户可见控件、通知              |
| `esp/`    | ESP 元素、标签、条形元素、实体覆盖显示             |
| `net/`    | HTTP、WebSocket、异步网络通信             |
| `game/`   | 读取玩家状态、实体状态、伤害数据、武器状态、游戏运行时数据     |
| `draw/`   | 基于帧的基础绘制、屏幕覆盖、watermark、crosshair |
| `math/`   | 向量逻辑、投影、缓动、几何 helper              |
| `file/`   | 沙盒文件 I/O、图片加载、本地持久化               |
| `input/`  | 热键状态、菜单热键、输入格式化                   |
| `log/`    | 诊断、调试输出、日志型 helper                |
| `script/` | 脚本生命周期、加载/卸载管理                    |
| `time/`   | frame count、时序节奏、基于时间的节流          |
| `config/` | plan switching、配置读写、武器配置 helper   |
| `json/`   | JSON 编码/解码工具或 JSON 密集型脚本          |
| `mixed/`  | 没有单一主导模块的复杂脚本                     |

如果一个脚本使用很多模块，应按照用户可见的主要用途分类，而不是按照它导入的每一个模块分类。

示例：

| 脚本用途                              | 分类        |
| --------------------------------- | --------- |
| 使用 `draw.*` 绘制屏幕中心准星              | `draw/`   |
| 使用 `esp.add(...)` 绘制 loot ESP 标签  | `esp/`    |
| 读取 `game.entities.*` 并写日志的伤害记录器   | `game/`   |
| 带按钮和通知的菜单面板                       | `gui/`    |
| 使用 HTTP 的远程版本检查                   | `net/`    |
| 使用 config path 的武器参数切换器           | `config/` |
| 同等程度组合 GUI、draw、game、config 的复杂脚本 | `mixed/`  |

## 脚本资产命名规则

成品脚本文件名应使用以下格式：

```text
<category>__<asset_name>__vNN.lua
```

示例：

```text
draw__center_crosshair__v01.lua
esp__loot_marker__v01.lua
gui__quick_toggle_panel__v02.lua
game__damage_logger__v01.lua
config__weapon_profile_switcher__v03.lua
mixed__combat_overlay_panel__v01.lua
```

规则：

* 使用小写英文文件名。
* 名称内部使用 `_`。
* 文件名分段之间使用双下划线 `__`。
* 使用 `v01`、`v02`、`v03` 表示资产级可见版本。
* 不要使用空格。
* 不要使用 `test.lua`、`new.lua`、`final.lua`、`fixed.lua` 这类模糊名称。

分类前缀应与目录名一致。

示例：

```text
scripts/finished/draw/draw__center_crosshair__v01.lua
```

## 归档命名规则

归档脚本应保留原始资产文件名，并增加时间戳和原因。

推荐格式：

```text
YYYYMMDD-HHMM__reason__original_filename.lua
```

示例：

```text
20260610-1430__before_gui_options_added__draw__center_crosshair__v01.lua
```

文件名中的原因应使用简短英文。
需要详细说明时，写入 `NOTES.md`。

## 创建新脚本的工作流

当 Codex 被要求创建新的 HApex3.0 Lua 脚本时：

1. 读取 `AGENTS.md`。
2. 只在需要时读取 `references/` 下的相关文件。
3. 判断脚本的主要分类。
4. 如果脚本是探索性产物，创建在 `scripts/_workbench/`。
5. 如果需求清晰且输出目标是资产，可直接创建在 `scripts/finished/<category>/`。
6. 使用规定的文件名格式。
7. 添加简体中文文件头注释。
8. 只在脚本内部添加有价值的简体中文注释。
9. 新增成品资产时，更新 `CATALOG.md`。
10. 如果无法运行 HApex3.0 环境，说明仍需哪些运行时验证。

## 修改已有成品脚本的工作流

当修改 `scripts/finished/` 下已有脚本时：

1. 读取现有脚本。
2. 理解其当前用途和分类。
3. 重大修改前，先归档旧版本。
4. 如果资产身份不变，可直接在原成品脚本上修改。
5. 如果新需求明显改变用途，应创建新的资产文件。
6. 更新 `CATALOG.md`。
7. 在修改摘要中说明归档路径。

重大修改包括：

* 改变主要行为
* 改变主要模块分类
* 替换 UI 模型
* 改变 config path 行为
* 重写实体遍历逻辑
* 替换网络或时序逻辑
* 从单一功能脚本改成多功能脚本

小修改不一定需要归档副本，但如果旧版本未来可能有参考价值，建议归档。

## 基于旧脚本分叉新脚本的工作流

当用户要求基于旧脚本创建新脚本时：

1. 搜索 `scripts/finished/` 和 `scripts/archive/`。
2. 使用最接近需求的现有脚本作为基础。
3. 如果新行为明显不同，应创建新的资产名。
4. 除非用户明确要求，否则不要覆盖旧脚本。
5. 更新 `CATALOG.md`。
6. 保留旧脚本作为参考资产。

## Lua 脚本注释语言

生成的 Lua 脚本注释默认必须使用**简体中文**，除非用户明确要求其他语言。

这适用于：

* 文件头注释
* 行内解释性注释
* Lua 文件内的人工验证说明

代码标识符、API 名称、模块名称和运行时要求的字符串，应保持 HApex3.0 Lua 所需的语言或格式。

推荐文件头风格：

```lua
-- 功能：在屏幕中心绘制一个可配置的准星提示。
-- 分类：draw
-- 使用 API：event、draw、gui、log。
-- 时序：draw.* 必须在 frame_update 中逐帧调用。
-- 验证：需要在 HApex3.0 实际运行环境中确认位置、颜色和缩放效果。
```

脚本内部注释应解释“为什么”，而不是解释显而易见的“做了什么”。

好的注释：

```lua
-- 双机环境下不能读取玩家侧键盘，因此这里使用菜单热键状态。
```

应避免：

```lua
-- 设置 x 为 10
local x = 10
```

## Lua 脚本生成规则

生成或编辑 `.lua` 文件时，应遵守 `AGENTS.md` 中的完整规则。

重要摘要：

* 不要臆造未文档化的 HApex3.0 Lua API。
* 需要 API 细节时，查询 `references/api-reference.md`。
* 需要完整可运行模式时，查询 `references/examples.md`。
* 涉及生命周期、时序、IPC 或项目结构时，查询 `references/guide.md`。
* 将 `draw.*` 调用放在 `event.on("frame_update", function(e) ... end)` 内。
* 对有状态对象方法使用冒号调用，例如 `net.http:get(...)`、`net.ws:connect(...)` 和 `gui.notify:success(...)`。
* 遍历 `game.entities.players`、`game.entities.loots` 或 `game.entities.projectiles` 时使用 `pairs`。
* 双机环境下，不要使用 `input.is_down(vk)` 判断玩家侧按键状态。
* 脚本注册成功后使用 `log.success("...")`，不要使用 `print`。
* 用户可见反馈使用 `gui.notify:info / :success / :warn / :error`。
* 不要为 HApex3.0 会自动释放的资源添加不必要的 unload 清理逻辑。

## 资产状态标签

在 `CATALOG.md` 中使用以下状态标签：

| 状态             | 含义                |
| -------------- | ----------------- |
| `draft`        | 已创建但尚未审查          |
| `experimental` | 有用，但需要运行时测试或进一步验证 |
| `stable`       | 已审查，并计划复用         |
| `archived`     | 为参考保留的旧版本或被替换版本   |
| `deprecated`   | 不建议用于新工作，但保留历史记录  |

## Codex 云端用法

本仓库设计用于 Codex 云端。

预期工作流：

```text
GitHub 私有仓库
        ↓
Codex 云端 checkout 仓库
        ↓
Codex 读取 AGENTS.md
        ↓
必要时 Codex 读取 README.md 以理解资产工作流
        ↓
Codex 按需加载 references/
        ↓
Codex 创建、修改、归档或登记 Lua 脚本
        ↓
用户审查 diff 或 pull request
```

Codex 云端不应依赖本地机器路径，例如：

```text
~/.codex/hapex3-lua/
~/.codex/AGENTS.md
```

所有必需项目上下文都应提交到本仓库。

## 维护原则

* `README.md` 是英文原生仓库概览。
* `README_CN.md` 是 `README.md` 的简体中文翻译。
* `AGENTS.md` 是 AI 编码行为的权威指令文件。
* `SKILL.md` 是兼容 Claude Code 的 skill 入口。
* `references/` 存放大型 API 参考、指南和示例。
* `scripts/_workbench/` 存放临时工作文件。
* `scripts/_templates/` 存放可复用起点模板。
* `scripts/finished/` 存放可复用脚本资产。
* `scripts/archive/` 存放旧版本、替代版本或废弃版本。
* `CATALOG.md` 跟踪重要资产及其状态。
* 不要提交密钥、账号数据、私人机器路径或个人配置。
* 如果参考文档与实际运行行为冲突，应记录差异，并优先采用已验证的实际运行行为。

## 适用范围

本仓库适用于：

* 持续生成 HApex3.0 / HOOZi Lua 脚本
* 修改已生成的现有脚本
* 维护分类化脚本资产库
* 归档有用的旧脚本版本
* 创建 ESP、watermark、notification、hotkey hint、damage logger、config helper、network helper 或类似 Lua 脚本
* 将旧脚本迁移到当前 HApex3.0 Lua API

本仓库不适用于：

* 普通 HApex3.0 产品使用问题
* 无关的通用 Lua 项目
* 把 Git 历史作为唯一脚本归档
* 安装原始 `hapex3-lua-skill.zip` 包
