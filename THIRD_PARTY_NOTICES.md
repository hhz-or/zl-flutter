# 第三方组件与许可

本仓库包含的字体、语料与设定均来自第三方，以下是出处与许可说明。

---

## 1. 霞鹜文楷（LXGW WenKai）—— 中文字形

* 出处：<https://github.com/lxgw/LxgwWenKai>
* 许可：SIL Open Font License 1.1，全文见
  [`assets/fonts/LICENSE-LXGWWenKai.txt`](assets/fonts/LICENSE-LXGWWenKai.txt)
* 版权：Copyright 2021-2026 LXGW，并声明保留字体名
  `'霞鹜'`、`'霞鶩'`、`'落霞孤鹜'`、`'落霞孤鶩'`、`'LXGW'`。

### 为什么随应用分发的字体叫 `WenKaiZL` 而不是 `LXGW WenKai`

原版网页直接分发 **24.3 MiB** 的原始 TTF，属于「原样分发」，没有任何问题。
本仓库为了体积把它**裁剪成子集**（`tools/subset_fonts.py`，只保留实际用到的
700 多个码位）。子集在 OFL 里属于 **Modified Version**。

该字体的 OFL 对保留字体名给了一条附加许可：保留名可以继续用在子集里，但**仅限
「纯粹为网页字体分发」所做的子集**，且不得作为可安装的桌面字体分发。本项目会构建
**可安装的 Windows 应用**，不在该附加许可范围内，因此按 OFL 的默认规则——Modified
Version 不得使用保留字体名——把这份子集改名为 `WenKaiZL`
（`tools/subset_fonts.py` 里的 `LXGW_SUBSET_FAMILY`）。

**改的只是名字**：字形、字距、度量全部与原字体一致，应用外观没有任何变化。
字体文件里同时附带了完整的 OFL 全文。

> 如果你更希望保留原名：把 `tools/subset_fonts.py` 的 `LXGW_SUBSET_FAMILY` /
> `LXGW_SUBSET_PS_NAME`、`pubspec.yaml` 的 `family:` 与 `lib/core/theme/app_theme.dart`
> 的 `kCjkFontFamily` 一起改回 `LXGW WenKai` 即可——但那样在分发桌面安装包时
> 就不再满足 OFL 的保留名条款。

---

## 2. Inter —— 西文字形

* 出处：<https://github.com/rsms/inter>（Google Fonts 上的同名字体同源）
* 许可：SIL Open Font License 1.1，全文见
  [`assets/fonts/LICENSE-Inter.txt`](assets/fonts/LICENSE-Inter.txt)
* 版权：Copyright (c) 2016 The Inter Project Authors

Inter 的 OFL **没有**声明保留字体名，因此这里直接从可变字体实例化出
400/500/600/700 四个静态字面并做子集裁剪，无需改名。

---

## 3. 语料与设定

* 语料（场景 / 行为 / 补充 / 彩蛋四组共 130 句）与页面结构、样式、动画时序
  均逐字转录自 <https://github.com/hhz-or/web-instruction>。
* 设定出处：Project Moon《废墟图书馆》/《边狱公司》中的「食指」阵营。
* 本应用是非商业同人二创，与原作及其发行方没有任何隶属关系。
  所有「指令」都是随机拼装出来的虚构内容，**不构成任何真实建议**。

---

## 4. 原项目已移除的第三方脚本

原版网页带有 Umami 统计与 giscus 评论区，本仓库**均未引入**（无任何第三方
运行时脚本、无埋点、无 Cookie）。
