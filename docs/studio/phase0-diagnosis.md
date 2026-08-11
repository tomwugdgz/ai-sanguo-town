# My AI Town · Phase 0 阶段诊断（主理人产物）

> 诊断人：游承峰（游戏开发工作室主理人）｜日期：2026-08-11
> 评审强度：**Lean 精简流程**｜当前路由：**Phase 7 发布准备（先冲发布）**

## 1. 项目身份
- **名称**：My AI Town（我的 AI 小镇）
- **类型**：Godot 4.7 开发的单机 LLM 驱动生活模拟游戏
- **状态**：Early Access 内测中（2026-08-08 启动），Windows + macOS 双端
- **仓库**：README 指向 github.com/mewamew/my_ai_town（本工作副本未检出 git remote，需核实）

## 2. 已落地事实（实测，非推测）
- **核心闭环已通**：`game/agent/`（居民决策·记忆·模型接入）、`game/world/`（世界规则·地图·表现）、`game/ui/`（启动·HUD·各界面）、`game/audio/`、`game/characters/`、`game/residents/`、`game/prompts/` 全部齐备。README 确认"行为结果、记忆与界面呈现形成完整闭环"。
- **QA 脚手架成熟**：`game/tests/` 含 50+ 个 `.gd` 测试 + 正式发布验收 shell 运行器（`run_complete_formal_release_validation.sh`、`run_formal_release_story_suite.sh`、`run_formal_release_story_suite_parallel.sh` 等），覆盖合同测试 / 集成测试 / 运行验收。
- **发布资产雏形在**：`game/export_presets.cfg` 存在；变更日志两份（`更新日志.md`、`发行更新记录.md`），每日更新至 2026-08-11。

## 3. 七阶段定位
| 阶段 | 状态 |
|---|---|
| 1 概念 / 2 系统设计 / 3 技术搭建 / 4 预制作 | ✅ 实质完成（垂直切片已作为内测发出） |
| 5 制作 | ✅ 大部分完成 |
| **6 打磨** | 🔶 已实质性处于此阶段（8/8~8/11 每日更新=修复/低配兼容/全屏适配/音乐轮换） |
| **7 发布** | 🟡 半开：内测已发，但 README 明写"桌面下载版将在准备完成后发布到 GitHub Releases"——**尚未正式发**；macOS 未公证 |

**结论**：项目处在 Phase 6 打磨、紧贴 Phase 7 发布门槛。按用户决策，下一步优先 **Phase 7 发布准备**。

## 4. 缺口与文档债
- ❌ 无 `design/gdd/`、无 `docs/architecture/`、无 `production/epics/`——典型"代码先行、文档欠账"。Lean 流程下暂不作为优先项，留待发版后补轻量版。
- ⚠️ 本工作副本 `git remote` 为空 → 发版前必须核实仓库与 Releases 写入权限。
- ⚠️ macOS 未做 Apple 签名/公证（README 已声明）→ 发版阻塞项之一。

## 5. 路由决策（Lean + 先冲发布）
- **主派**：`release-ops-lead` → 发布清单 + GitHub Releases 桌面版构建发布步骤 + 变更日志/发布说明 + macOS 公证计划 + 回滚方案 + 上线检查单。Output：`production/release/`
- **随后门控**：`quality-lead` → 基于现有 `game/tests/` 正式发布验收脚本做最终 QA 门（签字放行）。
- 打磨期（Phase 6）的 `engineering-lead` 性能剖析 / `art-director` 资产审计 / `audio-director` 音频打磨，作为发版后的持续项，Lean 下不单独开重流程。

## 6. 已知风险与缓解
| 风险 | 缓解 |
|---|---|
| 无 git remote / 无 Releases 写权 | 发版前先核实仓库归属与 token 权限 |
| macOS 未公证导致首次打开被拦截 | 发布说明明确提示；排期公证或提供绕过指引 |
| 桌面构建未经验证直接发 | 先用 export_presets + 正式验收脚本在本地出包自测 |
| 文档债导致发版后维护困难 | 发版后补轻量 GDD/架构速览 |
