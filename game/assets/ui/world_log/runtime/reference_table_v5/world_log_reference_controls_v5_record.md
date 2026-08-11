# 世界日志参考图控件 v5 生成记录

## 用途

按 `candidates/candidate_v3/world_log_table_candidate_v3.png` 的现有视觉语言补齐运行时控件素材，不重新设计界面。Godot 继续绘制全部动态文字。

## ImageGen 输入

- 参考图：`game/assets/ui/world_log/candidates/candidate_v3/world_log_table_candidate_v3.png`
- 正式总览：`game/assets/ui/world_log/final/world_log_ui_system_v1.png`
- 生成原图：`world_log_reference_controls_v5_source.png`
- 透明底图集：`world_log_reference_controls_v5_alpha.png`

## 生成提示词

严格复刻参考图里的像素游戏 UI 素材，不做新的视觉设计。输出品红纯色背景上的 sprite atlas：浅米色薄边下拉筛选框 normal/hover、居民/标签/日历图标、深棕小箭头、未选和橙色勾选框、关闭与返回按钮、棕橙色虚线和实线分隔线、细竖向时间线节点与连接线、未读圆点。材质、色板、线宽、像素密度、圆角和阴影必须与参考图一致；不要文字、标题、卡片、状态标签或额外装饰。

## 运行规则

- 筛选框素材保留右侧箭头，运行时不再叠加第二个箭头。
- 当前页面按候选 v3 在标题栏显示未读总数；图集中的复选框保留为同风格控件素材。
- 详情保持参考图的普通排版：居中标题、两行元信息、分隔线、正文或时间线。
- 表格保持单行窄行；摘要保留在详情数据和悬停提示中，不作为第二行挤高表格。
