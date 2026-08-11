# 三国人物映射表（resident_catalog 轻量文案改造）

> 说明：本表为 `resident_catalog.tk_draft.json` 的人工审看映射。
> **仅重写身份文案字段**（`name / age / desire / personality / speech / interests / customInterests / occupation.name`）。
> `residentId`、`attributes.appearance`、`presentation` 整块、`occupation.workplacePlace` **逐字保留**，未改动。
> `interests` 仅取自 `interest_catalog.json` 现有键；`gender` 与原槽位一致。

## 女性槽位（7）

| 原 residentId | 原姓名 | 新三国人物 | 性别 | 新职衔 | 新年龄 | 一句话人设依据（史实/演义出处） |
|---|---|---|---|---|---|---|
| resident_hanako_01 | 花子 | 大乔 | 女 | 茶博士 | 28 | 江东二乔之一，国色端庄、善待客（演义「江东乔公二女」），掌茶肆如掌中馈。 |
| resident_xu_zhao_01 | 许照 | 蔡文姬 | 女 | 书吏 | 41 | 东汉文学家蔡邕女，归汉后整理典籍、精于琴（胡笳十八拍），沉静博学。 |
| resident_tang_xiaoman_01 | 唐小满 | 貂蝉 | 女 | 商贾 | 24 | 连环计主角，周旋董卓吕布之间，善揣摩人心、穿针引线（演义）。 |
| resident_jiang_cheng_01 | 姜澄 | 小乔 | 女 | 花贾 | 22 | 二乔之妹，周瑜妻，清雅绝色、惜花弄影（演义）。 |
| resident_su_tang_01 | 苏棠 | 孙尚香 | 女 | 膳夫 | 26 | 孙权妹，枭姬，性烈豪爽、不让须眉（演义「弓腰姬」）。 |
| resident_bai_zhi_01 | 白芷 | 甄姬 | 女 | 医官 | 27 | 文昭甄皇后，温婉仁厚、灵秀有识（洛神赋原型）。 |
| resident_mi_ya_01 | 米芽 | 黄月英 | 女 | 巧匠 | 26 | 诸葛亮妻，传说善机关（木牛流马），聪慧巧思（演义/民间）。 |

## 男性槽位（9）

| 原 residentId | 原姓名 | 新三国人物 | 性别 | 新职衔 | 新年龄 | 一句话人设依据（史实/演义出处） |
|---|---|---|---|---|---|---|
| resident_lin_lan_01 | 林岚 | 诸葛亮 | 男 | 园吏 | 40 | 卧龙，「躬耕于南阳」、淡泊宁静、事必躬亲（出师表/演义）。 |
| resident_zhou_jiming_01 | 周既明 | 黄忠 | 男 | 库吏 | 58 | 老当益壮、严谨持重，定军山斩夏侯渊（演义）。 |
| resident_luo_yuan_01 | 罗远 | 张飞 | 男 | 匠作 | 45 | 燕人猛将，性烈重义、粗中有细，传说善书画（演义/民间）。 |
| resident_qiao_yiming_01 | 乔一鸣 | 马超 | 男 | 督运 | 28 | 锦马超，年少骁勇性烈、为父兄复仇急切（演义）。 |
| resident_lu_qingzhou_01 | 陆青舟 | 赵云 | 男 | 渔户 | 38 | 常山赵子龙，忠勇漂泊、进退有度（长坂坡/演义）。 |
| resident_xie_mian_01 | 谢眠 | 周瑜 | 男 | 乐官 | 34 | 美周郎，「曲有误，周郎顾」，风流儒雅通音律（演义）。 |
| resident_wen_xu_01 | 闻叙 | 刘备 | 男 | 主簿 | 48 | 汉昭烈帝，仁德宽和、善聚人重信义（演义）。 |
| resident_cheng_yan_01 | 程砚 | 司马徽 | 男 | 校书郎 | 63 | 水镜先生，长者学者、知人善任、口不臧否（演义「伏龙凤雏」）。 |
| resident_shen_qiao_01 | 沈桥 | 关羽 | 男 | 邮传令 | 40 | 千里走单骑护嫂、重然诺，夜读春秋（演义）。 |

## 校验要点（供人工核对）

- ✅ 16 个 `residentId` 与原文逐字一致，未重排。
- ✅ 7 女 9 男性别与原槽位一致；新人物性别匹配。
- ✅ `attributes.appearance`（look_00…look_15）逐字保留。
- ✅ `presentation`（locationLabel / spritePath / portraitPath）逐字保留，portrait 路径未动。
- ✅ `occupation.workplacePlace`（花房咖啡馆/社区花园/图书馆/码头仓库/独立市集/工作坊/公共食堂/渔港/中心广场/诊所/镇公所/小镇道路）逐字保留。
- ✅ `interests` 全部取自 `interest_catalog.json` 现有键，每人在 1–3 个上限内。
- ⚠️ 未改 `town_common_knowledge.md` 与 `interest_catalog.json`（本次轻量改造，世界观/兴趣表保持原样）。
