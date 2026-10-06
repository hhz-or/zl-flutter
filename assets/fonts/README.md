# assets/fonts — 子集化流水线说明

本目录下的五个字体文件**全部是生成物**，不要手工替换。它们由
[`tools/subset_fonts.py`](../../tools/subset_fonts.py) 从 `指令/` 里的原始字体
现场生成。

| 输出 | 来源 | 生成方式 |
| --- | --- | --- |
| `Inter-Regular.ttf` | `指令/Inter-VariableFont_opsz,wght.ttf` | `wght=400`、`opsz=14.0` 静态实例化后子集化 |
| `Inter-Medium.ttf` | 同上 | `wght=500` |
| `Inter-SemiBold.ttf` | 同上 | `wght=600` |
| `Inter-Bold.ttf` | 同上 | `wght=700` |
| `WenKaiZL-Regular.ttf` | `指令/LXGWWenKai-Regular.ttf` | 直接子集化（CJK 部分）后**改名** |

> 中文子集为什么叫 `WenKaiZL` 而不是 `LXGW WenKai`：子集在 OFL 意义上属于
> Modified Version，而霞鹜文楷的 OFL 声明了 Reserved Font Name，其附加许可只
> 覆盖「纯为网页字体分发」的子集，不包括可安装的桌面应用。本项目会打包 Windows
> 安装包，因此按 OFL 默认规则改名。**字形完全一致**，详见仓库根目录的
> [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md)。改名的常量是脚本里的
> `LXGW_SUBSET_FAMILY` / `LXGW_SUBSET_PS_NAME`。

本目录同时还附带两份许可证全文：`LICENSE-LXGWWenKai.txt`、`LICENSE-Inter.txt`
（OFL 1.1 要求随字体一起分发）。

## 重新生成

```bash
# 重新生成五个字体 + 打印体积表 + 校验（默认行为）
python tools/subset_fonts.py

# 只校验：任何一个收集到的码点不在五个字体的 cmap 里就退出码非 0
python tools/subset_fonts.py --verify

# 只看体积表
python tools/subset_fonts.py --report

# 顺便重新生成 assets/images/instruction.png、instruction.webp
# 以及 web/favicon.png、web/icons/*
python tools/subset_fonts.py --images
```

依赖：Python 3.13 + `fonttools`（含 `pyftsubset`）。`--images` 另外需要 `Pillow`。

## 字符集是怎么来的

脚本每次运行都会**重新解析仓库**，没有任何硬编码字符表：

1. `指令/script.js` —— 用一个小型状态机扫描所有字符串字面量（跳过 `//`、`/* */`
   注释，正确处理 `\uXXXX` / `\u{XXXXXX}` 转义），CJK 语料的来源；
2. `lib/l10n/app_en.arb`、`lib/l10n/app_zh.arb` —— 解析 JSON，取全部字符串值；
3. `lib/**/*.dart` —— 全部字符串字面量（同样跳过注释、支持 `r'...'` 原始字符串、
   三引号、代理对）；
4. `kScrambleGlyphs` —— 从
   `lib/features/generator/widgets/scramble_text.dart` 里**解析**出来，
   而不是抄一份常量（解析失败会退回到内置副本并打印警告）；
5. 可打印 ASCII、常用中文标点（`，。、；：？！「」『』（）—…·《》〈〉`）与数字。

控制/格式类码点（`\n`、BOM、零宽空格等）会被统计后忽略：它们永远不需要字形。

收集结果会按 CJK / 非 CJK 分流：

* **Inter** 拿到全部非 CJK 码点 +（ASCII、Latin-1、Latin Extended-A/B、
  General Punctuation、上下标、货币符号、字母式符号）+ 乱码字形集；
* **LXGW WenKai** 拿到全部 CJK 码点 + 同一套西文/标点区间，这样中文回退字体也能
  直接画出混排的拉丁字符，不需要二次回退。

## 关键取舍

* **先实例化、后子集化。** `opsz` 被钉在字体自身的默认值 `14.0`（即 Text 光学尺寸），
  只有两个轴都钉死才会得到**完全静态**的字面，`fvar`/`gvar`/`avar`/`HVAR`/`MVAR`/`STAT`
  全部消失；只钉 `wght` 会留下一整套 delta 数据。
* **OpenType 特性**：`--layout-features=auto`（默认）会各构建一次，比较
  `pyftsubset` 默认的 HarfBuzz 推荐特性列表与全量 `'*'`，只有 `'*'` 的代价不超过
  10 % 时才保留它。实测 Inter 的 `ss01`–`ss20` / `cv01`–`cv14` / `aalt` / `salt` /
  `frac` / `numr` / `tnum` 等风格集对一个霓虹文字应用毫无用处，却要贵 37 %，因此
  选用默认列表；LXGW WenKai 只贵 7.7 %，于是保留 `'*'`。想强制其中一种可以用
  `--layout-features default|all`。
* **hinting**：设为 `False`（等价 `--no-hinting`）。两个源字体都不含 TrueType
  字形指令，所以这一步只是丢掉 hinting 相关的表。`desubroutinize=false` 是无关选项：
  两个字面都是 `glyf` 轮廓的 TrueType，不是 CFF。
* **字形名**：丢弃（`post` 写成 format 3.0）。LXGW WenKai 有 46 788 个字形，为它们
  保留名字纯属浪费；Skia（Flutter web / CanvasKit）与 Chrome 光栅化都不需要名字。
  轮廓、`cmap`、`hmtx` 与 OpenType 布局表全部保留。
* `head.modified` 固定为源字体的值，输出可复现。

## 校验（`--verify`）

对第 1 步收集到的**每一个**码点，检查五个输出字体的 `cmap` 并集是否覆盖它；缺失的
字符会连同码点和来源（`路径:行号`）一起打印，进程退出码为 1。另外还会顺带检查是否有
收集到的字符被映射到零宽度字形（`cmap` 里有、但画出来是空的）。

参考体积（Flutter 3.47.5 / fontTools 4.63）：

| 文件 | 原始 | 子集化后 |
| --- | --- | --- |
| 四个 Inter 静态字面 | 874 708 B（可变字体，×4） | 约 98 KB / 个 |
| `WenKaiZL-Regular.ttf` | 25 486 932 B | 约 397 KiB |
