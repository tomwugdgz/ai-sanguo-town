# 世界日志控件素材 v4 生成记录

## 用途

这套素材用于世界日志的筛选控件、按钮、详情区、邮递详情和过程浏览。文字由 Godot 渲染，图片只提供像素外观和状态差异。

## 生成方式

- 工具：内置 ImageGen；
- 用例：`ui-mockup`；
- 参考图：`candidate_v3/world_log_table_candidate_v3.png`、`final/world_log_ui_system_v1.png`、`reference_table_v2/world_log_table_components_atlas_v2_source.png`；
- 原始输出：`world_log_controls_atlas_v4_source.png`；
- 去色键输出：`world_log_controls_atlas_v4_alpha.png`；
- 色键：`#ff00ff`。

## 最终提示词

按参考图的木框、羊皮纸、橙色选中态和一像素边缘，生成一张无文字的 Godot 世界日志控件素材板。素材板包含下拉框四态、箭头、按钮四态、未读开关两态、小图标按钮、详情标题条、四色信息标签、事件摘要条、过程条、口信纸张、翻页按钮、装饰分隔线，以及返回、关闭、刷新、信封、居民、类型、日期和未读图标。所有可拉伸框必须保留空白中心，颜色和紧凑比例对齐参考图；不生成界面截图、地图、人物、文字、数字或水印。背景使用纯色 `#ff00ff`，生成后本地去除背景并切分为运行时 PNG。

## 运行规则

- 控件背景使用 NinePatch 或 StyleBoxTexture 拉伸；
- 正文区域不使用生成文字；
- 下拉框弹出菜单、按钮状态、详情标签和过程条都使用本目录图片；
- 表格单元格继续使用 `reference_table_v2` 的单边一像素网格资源。
