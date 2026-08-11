# 世界日志正式视觉系统 v1

- 生成模式：ImageGen，参考图引导生成。
- 参考图：
  - `game/assets/ui/world_log/candidates/candidate_v3/world_log_table_candidate_v3.png`
  - `game/assets/ui/world_log/candidates/candidate_v3/world_log_cargo_detail_candidate_v3.png`
- 正式视觉基准：`game/assets/ui/world_log/final/world_log_ui_system_v1.png`
- 运行时表格资源：`game/assets/ui/world_log/runtime/reference_table_v2/`，以正式参考图为约束重新生成无文字组件图集，再切分为外框、纸张、详情框、筛选框、表格单元格、选中单元格、未读圆点和下拉箭头。
- 语义图标继续复用 `game/assets/ui/town_log/runtime/family/v3_imagegen/` 中已经过验收的 ImageGen 图片资源。

## 生成提示摘要

为像素风小镇模拟游戏设计一套简单、精致、商业游戏品质的“世界日志”界面系统。使用细木框、温暖羊皮纸、深棕正文和少量橙色选中状态；宽屏包含表格与详情双栏，窄屏包含单列表与整页详情。展示对话、医疗、售卖、搬运、生产、服务、天气、冲突和公告等事件。对话按说话者显示完整原文，每句旁不显示时间；事件详情按时间显示过程。底部单独展示可复用的木框、纸张、选中行、未读圆点、下拉、关闭和返回视觉组件。不要照搬任何商业游戏商标或原始美术。

## 实现约束

正式页面以 Godot 控件承载文字、筛选、表格、滚动和点击状态，只把生成图中的框体、纸张、按钮和图标作为可复用图片资源；不得把整张效果图作为不可交互背景。
