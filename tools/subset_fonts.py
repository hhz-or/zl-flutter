#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Font pipeline for flutter_zl — static instancing + subsetting + verification.

The app ships five font files (declared in ``pubspec.yaml``)::

    assets/fonts/Inter-Regular.ttf          <- 指令/Inter-VariableFont_opsz,wght.ttf
    assets/fonts/Inter-Medium.ttf           <-       "
    assets/fonts/Inter-SemiBold.ttf         <-       "
    assets/fonts/Inter-Bold.ttf             <-       "
    assets/fonts/WenKaiZL-Regular.ttf      <- 指令/LXGWWenKai-Regular.ttf (renamed subset)

Upstream they are 0.85 MB (Inter VF) and 24.9 MB (LXGW WenKai).  Almost none of
that is ever drawn: the app renders a few hundred Chinese characters taken from
``指令/script.js`` plus the UI strings from the ARB/localisation files.  This
script collects *exactly* the code points that can reach the screen, builds four
static Inter instances out of the variable font, subsets every face down to that
set, and then proves the result by re-reading the ``cmap`` of the files it wrote.

Usage
-----
    python tools/subset_fonts.py                # rebuild the five fonts + report + verify
    python tools/subset_fonts.py --verify       # verification only, exit != 0 on failure
    python tools/subset_fonts.py --report       # size table only
    python tools/subset_fonts.py --images       # also (re)generate the logo/web icons
    python tools/subset_fonts.py --layout-features all   # force `--layout-features='*'`

Nothing here is hard-coded: the character set is parsed out of the repository on
every run, so adding a sentence to the corpus (or a string to an ARB file) only
requires re-running this script.

Design notes / deliberate choices
---------------------------------
* **Instancing order** — instance first, then subset.  ``opsz`` is pinned to its
  own default (14.0) so each ``wght`` stop becomes a *fully* static face
  (``fvar``/``gvar``/``avar``/``HVAR``/``MVAR``/``STAT`` all disappear).  Pinning
  ``opsz`` is not bookkeeping: leaving it live would keep ``gvar`` and the whole
  delta machinery inside every output file.
* **Layout features** — ``auto`` (default) builds each family twice, once with
  pyftsubset's default (HarfBuzz-recommended) feature list and once with the
  everything-goes ``'*'``, and keeps ``'*'`` only when it costs <= 10 % more.
  For Inter the stylistic sets (``ss01``-``ss20``, ``cv01``-``cv14``, ``aalt``,
  ``salt``, ``frac``, ``numr``, ``tnum``, ...) are dead weight for a neon-text
  app and are dropped; whatever the probe decides is printed.
* **Hinting** — ``--no-hinting`` equivalent (``Options.hinting = False``).  Neither
  source font carries TrueType glyph instructions, so this only drops the
  hinting tables.  ``desubroutinize`` is irrelevant here: both faces are
  ``glyf``-flavoured TrueType, not CFF.
* **Glyph names** — dropped (``post`` becomes format 3.0).  LXGW WenKai has
  46 788 glyphs; carrying names for them is pure weight, and neither Skia
  (Flutter web / CanvasKit) nor Chrome needs them to rasterise.  Outlines,
  ``cmap``, ``hmtx`` and the OpenType layout tables are all preserved.

The script is pure standard library + fontTools/Pillow, writes only the output
files (no temporary directories) and is safe to re-run.
"""

from __future__ import annotations

import argparse
import io
import json
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, Iterable, Iterator, List, Optional, Sequence, Set, Tuple

# --------------------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[1]
FONTS_DIR = REPO_ROOT / "assets" / "fonts"
IMAGES_DIR = REPO_ROOT / "assets" / "images"
WEB_DIR = REPO_ROOT / "web"
#: Windows 运行器的应用图标（本地桌面是主要目标，不该用 Flutter 默认图标）。
WINDOWS_ICON = REPO_ROOT / "windows" / "runner" / "resources" / "app_icon.ico"

SRC_DIR = REPO_ROOT / "指令"
INTER_VF = SRC_DIR / "Inter-VariableFont_opsz,wght.ttf"
LXGW_SRC = SRC_DIR / "LXGWWenKai-Regular.ttf"
SCRIPT_JS = SRC_DIR / "script.js"
LOGO_PNG = SRC_DIR / "instruction.png"

LIB_DIR = REPO_ROOT / "lib"
#: 应用与原站一样只有中文，因此只有一份 ARB。
ARB_FILES: Tuple[Path, ...] = (LIB_DIR / "l10n" / "app_zh.arb",)
SCRAMBLE_DART = LIB_DIR / "features" / "generator" / "widgets" / "scramble_text.dart"

#: ``wght`` stops to instantiate.  The subfamily strings are the ones the Inter
#: variable font itself declares for those stops (see its ``fvar`` table).
INTER_INSTANCES: Tuple[Tuple[str, int], ...] = (
    ("Regular", 400),
    ("Medium", 500),
    ("SemiBold", 600),
    ("Bold", 700),
)

#: ``opsz`` (optical size) value pinned while instancing.  14.0 is the font's own
#: default and the "Text" cut — the right one for UI copy at 14-40 px.
OPSZ_PIN = 14.0

LXGW_OUT = FONTS_DIR / "WenKaiZL-Regular.ttf"

#: 子集化 = OFL 意义上的「Modified Version」。霞鹜文楷的 OFL 声明了
#: Reserved Font Name（'霞鹜'、'霞鶩'、'落霞孤鹜'、'落霞孤鶩'、'LXGW'），
#: 其附加许可只允许「**纯为网页字体分发**而做的子集」继续沿用这些名字，
#: 且不得作为可安装的桌面字体分发。本项目会打包出可安装的 Windows 应用，
#: 不在该附加许可范围内，因此按 OFL 默认规则把子集改名为不含保留名的名字。
#: 字形完全一致，只是名字变了；来源与致谢见 THIRD_PARTY_NOTICES.md。
LXGW_SUBSET_FAMILY = "WenKaiZL"
LXGW_SUBSET_PS_NAME = "WenKaiZL-Regular"

#: Used only if ``kScrambleGlyphs`` cannot be parsed out of the Dart source.
SCRAMBLE_FALLBACK = (
    "ABCDEFGHIJKLMNOPQRSTUVWSYZ0123456789$#@&*%?±!<>-_\\/[]{}—=+^"
    "abcdefghijklmnopqrstuvwsyz"
)

#: Marker characters that identify the real glyph-set literal.
SCRAMBLE_MARKERS = "$#@&*%?!<>"

# --------------------------------------------------------------------------------------
# Required ranges / literal sets
# --------------------------------------------------------------------------------------

#: Printable ASCII (U+0020 .. U+007E).
ASCII_PRINTABLE = range(0x20, 0x7F)

#: The exact punctuation the corpus and UI rely on, plus digits.
REQUIRED_CJK_PUNCTUATION = "，。、；：？！「」『』（）—…·《》〈〉"
REQUIRED_DIGITS = "0123456789"

#: Ranges always requested from the Latin face (Inter) *and* from the CJK face
#: (LXGW WenKai), so the fallback can also draw stray Latin without a second
#: fallback hop.
LATIN_BASE_RANGES: Tuple[Tuple[int, int], ...] = (
    (0x0020, 0x007E),  # Basic Latin (printable ASCII)
    (0x00A0, 0x00FF),  # Latin-1 Supplement
    (0x0100, 0x017F),  # Latin Extended-A
    (0x0180, 0x024F),  # Latin Extended-B
    (0x2000, 0x206F),  # General Punctuation
    (0x2070, 0x209F),  # Super-/Subscripts
    (0x20A0, 0x20BF),  # Currency Symbols
    (0x2100, 0x214F),  # Letterlike Symbols
)

#: Code-point ranges that are "CJK business" and therefore only requested from
#: LXGW WenKai.  Halfwidth/fullwidth forms (U+FF00..) and the CJK punctuation
#: block (U+3000..) both live here.
CJK_RANGES: Tuple[Tuple[int, int], ...] = (
    (0x2E80, 0x2EFF),    # CJK Radicals Supplement
    (0x2F00, 0x2FDF),    # Kangxi Radicals
    (0x3000, 0x303F),    # CJK Symbols and Punctuation
    (0x3040, 0x30FF),    # Hiragana / Katakana
    (0x3100, 0x312F),    # Bopomofo
    (0x3130, 0x318F),    # Hangul Compatibility Jamo
    (0x3190, 0x319F),    # Kanbun
    (0x31A0, 0x31BF),    # Bopomofo Extended
    (0x31C0, 0x31EF),    # CJK Strokes
    (0x31F0, 0x31FF),    # Katakana Phonetic Extensions
    (0x3200, 0x32FF),    # Enclosed CJK Letters and Months
    (0x3300, 0x33FF),    # CJK Compatibility
    (0x3400, 0x4DBF),    # CJK Unified Ideographs Extension A
    (0x4E00, 0x9FFF),    # CJK Unified Ideographs
    (0xA960, 0xA97F),    # Hangul Jamo Extended-A
    (0xAC00, 0xD7AF),    # Hangul Syllables
    (0xF900, 0xFAFF),    # CJK Compatibility Ideographs
    (0xFE10, 0xFE1F),    # Vertical Forms
    (0xFE30, 0xFE4F),    # CJK Compatibility Forms
    (0xFF00, 0xFFEF),    # Halfwidth and Fullwidth Forms
    (0x20000, 0x2FA1F),  # CJK Extensions B..F + Compatibility Supplement
    (0x30000, 0x323AF),  # CJK Extensions G..H
)


def is_cjk(cp: int) -> bool:
    """True when *cp* belongs to a CJK-ish block (see [CJK_RANGES])."""
    return any(lo <= cp <= hi for lo, hi in CJK_RANGES)


#: Unicode general categories that occupy no glyph: control (``\n``, ``\t``),
#: format (BOM, zero-width space) and surrogate code points.
_NON_RENDERABLE_CATEGORIES = frozenset({"Cc", "Cf", "Cs"})


def is_renderable(cp: int) -> bool:
    """True when *cp* could ever need an outline in a font."""
    if not 0 <= cp <= 0x10FFFF:
        return False
    return unicodedata.category(chr(cp)) not in _NON_RENDERABLE_CATEGORIES


def _expand(ranges: Iterable[Tuple[int, int]]) -> Iterator[int]:
    for lo, hi in ranges:
        yield from range(lo, hi + 1)


# --------------------------------------------------------------------------------------
# Code-point bookkeeping
# --------------------------------------------------------------------------------------


@dataclass
class CharSet:
    """A set of code points plus, for each of them, where it was found.

    ``origin`` maps a code point to a short list of ``relative/path:line``
    provenance labels.  Those labels are what ``--verify`` prints when a
    character is missing from every output font, so they need to be actionable
    rather than exhaustive (hence the per-code-point cap).
    """

    origin: Dict[int, List[str]] = field(default_factory=dict)

    #: Control / format / surrogate code points seen in literals but never drawn
    #: (``\n`` inside an ARB string, a BOM, a zero-width space, ...).  Tracked so
    #: the summary can say how many were dropped instead of hiding them.
    skipped: Set[int] = field(default_factory=set)

    #: How many provenance labels to keep per code point.
    max_labels: int = 6

    def add(self, cp: int, label: str) -> bool:
        """Record *cp* as coming from *label*.  Returns True if it is new."""
        if not is_renderable(cp):
            self.skipped.add(cp)
            return False
        labels = self.origin.setdefault(cp, [])
        if label not in labels and len(labels) < self.max_labels:
            labels.append(label)
        return len(labels) == 1

    def add_text(self, text: str, label: str) -> int:
        """Record every scalar value in *text*.  Returns the number of new ones."""
        new = 0
        for cp in iter_code_points(text):
            if self.add(cp, label):
                new += 1
        return new

    def add_codepoints(self, codepoints: Iterable[int], label: str) -> int:
        new = 0
        for cp in codepoints:
            if self.add(cp, label):
                new += 1
        return new

    @property
    def codepoints(self) -> Set[int]:
        return set(self.origin)

    def __len__(self) -> int:
        return len(self.origin)

    def sources_of(self, cp: int) -> List[str]:
        return list(self.origin.get(cp, ()))


def iter_code_points(text: str) -> Iterator[int]:
    """Yield Unicode *scalar values* from *text*.

    Python strings already hold scalar values, except when a scanner has stuffed
    a lone UTF-16 surrogate into one (Dart ``\\uD83D\\uDE00``).  Surrogate pairs
    are recombined; a lone surrogate is dropped rather than poisoning the cmap
    lookup with an unencodable value.
    """
    i = 0
    n = len(text)
    while i < n:
        value = ord(text[i])
        if 0xD800 <= value <= 0xDBFF and i + 1 < n:
            low = ord(text[i + 1])
            if 0xDC00 <= low <= 0xDFFF:
                yield 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
                i += 2
                continue
        if 0xD800 <= value <= 0xDFFF:
            i += 1  # lone surrogate: not a valid scalar value
            continue
        yield value
        i += 1


# --------------------------------------------------------------------------------------
# Source scanners
# --------------------------------------------------------------------------------------

_SIMPLE_ESCAPES = {
    "n": "\n",
    "r": "\r",
    "t": "\t",
    "b": "\b",
    "f": "\f",
    "v": "\v",
    "0": "\0",
    "\\": "\\",
    "'": "'",
    '"': '"',
    "$": "$",
    "`": "`",
    "\n": "",  # line continuation
}


def _read_escape(src: str, i: int) -> Tuple[str, int, int]:
    """Decode the escape sequence starting at ``src[i] == '\\\\'``.

    Returns ``(decoded_text, next_index, newlines_consumed)``.  Unknown escapes
    keep the escaped character verbatim (Dart and JS both behave that way).
    """
    n = len(src)
    if i + 1 >= n:
        return "", i + 1, 0
    esc = src[i + 1]

    if esc == "u":
        # \uXXXX  (UTF-16 code unit)  or  \u{XXXXXX}  (scalar value)
        if i + 2 < n and src[i + 2] == "{":
            end = src.find("}", i + 3)
            if end != -1:
                digits = src[i + 3 : end]
                if digits and all(c in "0123456789abcdefABCDEF" for c in digits):
                    value = int(digits, 16)
                    if 0 <= value <= 0x10FFFF:
                        return chr(value), end + 1, 0
            return src[i : i + 2], i + 2, 0
        digits = src[i + 2 : i + 6]
        if len(digits) == 4 and all(c in "0123456789abcdefABCDEF" for c in digits):
            return chr(int(digits, 16)), i + 6, 0
        return src[i : i + 2], i + 2, 0

    if esc == "x":
        digits = src[i + 2 : i + 4]
        if len(digits) == 2 and all(c in "0123456789abcdefABCDEF" for c in digits):
            return chr(int(digits, 16)), i + 4, 0
        return src[i : i + 2], i + 2, 0

    if esc in _SIMPLE_ESCAPES:
        return _SIMPLE_ESCAPES[esc], i + 2, 1 if esc == "\n" else 0

    return esc, i + 2, 0


def scan_string_literals(src: str, *, lang: str) -> Iterator[Tuple[str, int]]:
    """Yield ``(literal_text, line_number)`` for every string literal in *src*.

    A hand-rolled scanner rather than a regex, because comments and strings
    contain each other's delimiters (``//`` inside a URL literal, an apostrophe
    inside a doc comment).  Handles:

    * ``//`` line comments and ``/* ... */`` block comments (Dart nests them, and
      nesting is harmlessly accepted for JS too),
    * single, double and triple-quoted literals,
    * Dart raw strings (``r'...'``) where backslash is *not* an escape,
    * ``\\n``, ``\\t``, ``\\xNN``, ``\\uXXXX``, ``\\u{XXXXXX}`` and ``\\$``,
    * ``${...}`` interpolation: the braces are treated as literal characters,
      which is fine — ``$``, ``{`` and ``}`` are ASCII and are shipped anyway.
    """
    i = 0
    n = len(src)
    line = 1

    while i < n:
        ch = src[i]

        if ch == "\n":
            line += 1
            i += 1
            continue

        # ---- comments -------------------------------------------------------
        if ch == "/" and i + 1 < n and src[i + 1] == "/":
            nl = src.find("\n", i)
            i = n if nl < 0 else nl
            continue

        if ch == "/" and i + 1 < n and src[i + 1] == "*":
            depth = 1
            i += 2
            while i < n and depth:
                if src.startswith("/*", i):
                    depth += 1
                    i += 2
                elif src.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    if src[i] == "\n":
                        line += 1
                    i += 1
            continue

        # ---- Dart raw string prefix ----------------------------------------
        raw = False
        if (
            lang == "dart"
            and ch in "rR"
            and i + 1 < n
            and src[i + 1] in "'\""
            and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] in "_$"))
        ):
            raw = True
            i += 1
            ch = src[i]

        # ---- string literals ------------------------------------------------
        if ch in "'\"":
            quote = ch
            triple = src.startswith(quote * 3, i)
            delim = quote * 3 if triple else quote
            start_line = line
            i += len(delim)
            buf: List[str] = []

            while i < n:
                if not raw and src[i] == "\\":
                    decoded, i, newlines = _read_escape(src, i)
                    buf.append(decoded)
                    line += newlines
                    continue
                if src.startswith(delim, i):
                    i += len(delim)
                    break
                if not triple and src[i] == "\n":
                    break  # unterminated single-line literal: bail out
                if src[i] == "\n":
                    line += 1
                buf.append(src[i])
                i += 1

            yield "".join(buf), start_line
            continue

        i += 1


# --------------------------------------------------------------------------------------
# Collection
# --------------------------------------------------------------------------------------


def _rel(path: Path) -> str:
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:  # pragma: no cover - only if a source lives outside the repo
        return str(path)


def extract_scramble_glyphs(warnings: List[str]) -> Tuple[str, str]:
    """Parse the ``kScrambleGlyphs`` literal out of ``scramble_text.dart``.

    Returns ``(glyphs, label)``.  Falls back to the hard-coded copy — with a
    warning — if the declaration moves or changes shape, because a silent
    omission here would show up as tofu boxes mid-animation.
    """
    label = f"{_rel(SCRAMBLE_DART)}:kScrambleGlyphs"
    try:
        text = SCRAMBLE_DART.read_text(encoding="utf-8")
    except OSError as exc:
        warnings.append(f"cannot read {_rel(SCRAMBLE_DART)} ({exc}); using built-in kScrambleGlyphs")
        return SCRAMBLE_FALLBACK, label

    candidates: List[str] = []
    for snippet in _iter_declarations(text, "kScrambleGlyphs"):
        parsed = "".join(lit for lit, _line in scan_string_literals(snippet, lang="dart"))
        if parsed:
            candidates.append(parsed)

    for parsed in candidates:
        if set(SCRAMBLE_MARKERS) <= set(parsed):
            return parsed, label

    if candidates:
        warnings.append("kScrambleGlyphs parsed but looks unlike the original glyph set")
        return candidates[0], label

    warnings.append("kScrambleGlyphs declaration not found; using built-in copy")
    return SCRAMBLE_FALLBACK, label


def _iter_declarations(text: str, name: str) -> Iterator[str]:
    """Yield the initialiser expression text of every ``<name> = ...;`` declaration."""
    start = 0
    while True:
        idx = text.find(name, start)
        if idx == -1:
            return
        start = idx + len(name)

        j = idx + len(name)
        while j < len(text) and text[j] not in "=;":
            j += 1
        if j >= len(text) or text[j] != "=" or text.startswith("==", j):
            continue

        depth = 0
        k = j + 1
        while k < len(text):
            c = text[k]
            if c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
            elif c == ";" and depth <= 0:
                break
            k += 1
        yield text[j + 1 : k]


def collect_characters(warnings: List[str]) -> Tuple[CharSet, str]:
    """Parse every source of truth on disk.  Returns ``(chars, scramble_glyphs)``."""
    chars = CharSet()

    # 1. The Chinese corpus, straight out of the original site's script. -----
    if SCRIPT_JS.is_file():
        text = SCRIPT_JS.read_text(encoding="utf-8")
        rel = _rel(SCRIPT_JS)
        literals = list(scan_string_literals(text, lang="js"))
        for literal, line in literals:
            chars.add_text(literal, f"{rel}:{line}")
        print(f"  {rel:<28}: {len(literals)} string literal(s)")
    else:
        warnings.append(f"{_rel(SCRIPT_JS)} not found — the CJK corpus was NOT collected")

    # 2. Both ARB files (every JSON string value, metadata included). ---------
    for arb in ARB_FILES:
        if not arb.is_file():
            warnings.append(f"{_rel(arb)} not found")
            continue
        try:
            payload = json.loads(arb.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            warnings.append(f"{_rel(arb)} is not valid JSON ({exc})")
            continue
        values = list(_walk_json_strings(payload))
        for value in values:
            chars.add_text(value, _rel(arb))
        print(f"  {_rel(arb):<28}: {len(values)} JSON string(s)")

    # 3. Every Dart string literal under lib/. --------------------------------
    dart_files = sorted(p for p in LIB_DIR.rglob("*.dart") if p.is_file())
    dart_literals = 0
    for path in dart_files:
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            warnings.append(f"cannot read {_rel(path)} ({exc})")
            continue
        rel = _rel(path)
        for literal, line in scan_string_literals(text, lang="dart"):
            dart_literals += 1
            chars.add_text(literal, f"{rel}:{line}")
    print(f"  lib/**/*.dart{'':<15}: {len(dart_files)} file(s), {dart_literals} literal(s)")

    # 4. The scramble animation glyph set (parsed, not hard-coded). -----------
    glyphs, glyph_label = extract_scramble_glyphs(warnings)
    chars.add_text(glyphs, glyph_label)
    print(f"  kScrambleGlyphs{'':<15}: {len(glyphs)} glyph(s)")

    # 5. Printable ASCII, CJK punctuation and digits. -------------------------
    chars.add_codepoints(ASCII_PRINTABLE, "<printable ASCII U+0020..U+007E>")
    chars.add_text(REQUIRED_CJK_PUNCTUATION, "<common CJK punctuation>")
    chars.add_text(REQUIRED_DIGITS, "<digits>")

    return chars, glyphs


def _walk_json_strings(node: object) -> Iterator[str]:
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for key, value in node.items():
            yield key
            yield from _walk_json_strings(value)
    elif isinstance(node, list):
        for item in node:
            yield from _walk_json_strings(item)


# --------------------------------------------------------------------------------------
# Splitting the collected set between the two families
# --------------------------------------------------------------------------------------


def build_subsets(chars: CharSet, scramble_glyphs: str) -> Tuple[Set[int], Set[int]]:
    """Split the collected code points into ``(inter_set, lxgw_set)``.

    * Inter (Latin) receives every *non-CJK* character that was collected — not
      merely the ones inside [LATIN_BASE_RANGES] — plus the standard Latin
      ranges, the scramble glyphs and ASCII.  Anything the corpus throws at it is
      therefore either drawn by Inter or reported by ``--verify``.
    * LXGW WenKai receives the CJK half plus the same Latin/punctuation ranges,
      so the fallback face can render stray Latin without a second fallback hop.
    """
    collected = chars.codepoints
    base = set(_expand(LATIN_BASE_RANGES)) | set(ASCII_PRINTABLE) | set(map(ord, scramble_glyphs))

    inter_set = {cp for cp in collected if not is_cjk(cp)} | base
    lxgw_set = {cp for cp in collected if is_cjk(cp)} | base
    return inter_set, lxgw_set


# --------------------------------------------------------------------------------------
# fontTools helpers
# --------------------------------------------------------------------------------------


def _require_fonttools():
    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
        from fontTools.varLib import instancer
    except ImportError as exc:  # pragma: no cover
        sys.exit(f"fontTools is required ({exc}); try: python -m pip install fonttools")
    return subset, TTFont, instancer


def subset_options(layout_features: Optional[Sequence[str]]):
    """Conservative pyftsubset options shared by both families.

    ``layout_features=None`` keeps pyftsubset's default (HarfBuzz-recommended)
    feature list; pass ``["*"]`` to keep everything.
    """
    subset, _TTFont, _instancer = _require_fonttools()
    opts = subset.Options()
    if layout_features is not None:
        opts.layout_features = list(layout_features)
    opts.hinting = False            # ~= --no-hinting (neither source is hinted)
    opts.desubroutinize = False     # ~= --desubroutinize=false (both faces use glyf)
    opts.glyph_names = False        # -> post format 3.0, invisible to Skia/Chrome
    opts.notdef_outline = True      # keep a visible tofu box instead of a blank
    opts.recalc_bounds = True       # refresh glyph bounding boxes after pruning
    opts.recalc_timestamp = False   # reproducible output
    opts.recommended_glyphs = False
    opts.legacy_cmap = False
    opts.symbol_cmap = False
    opts.name_IDs = [0, 1, 2, 3, 4, 5, 6, 16, 17]
    opts.name_legacy = False
    opts.name_languages = [0x0409]  # keep en-US names only
    opts.drop_tables = sorted(set(opts.drop_tables) | {"DSIG"})
    return opts


def subset_font(font, unicodes: Iterable[int], layout_features: Optional[Sequence[str]]):
    """Subset *font* in place down to *unicodes*."""
    subset, _TTFont, _instancer = _require_fonttools()
    subsetter = subset.Subsetter(options=subset_options(layout_features))
    subsetter.populate(unicodes=sorted(unicodes))
    subsetter.subset(font)
    return font


def serialize(font) -> bytes:
    buf = io.BytesIO()
    font.save(buf, reorderTables=True)
    return buf.getvalue()


def rename_face(font, family: str, subfamily: str, ps_name: str, weight: int) -> None:
    """Write a conventional name set plus the matching weight class.

    The four Inter outputs share one family name (``Inter``) and differ by
    ``OS/2.usWeightClass`` + subfamily — exactly how Google Fonts ships static
    instances of a variable family, and what ``pubspec.yaml`` assumes.
    """
    name = font["name"]
    full_name = f"{family} {subfamily}" if subfamily != "Regular" else family
    for platform_id, plat_enc_id in ((3, 1), (1, 0)):
        name.setName(family, 1, platform_id, plat_enc_id, 0x409)
        name.setName(subfamily, 2, platform_id, plat_enc_id, 0x409)
        name.setName(f"{ps_name};flutter_zl", 3, platform_id, plat_enc_id, 0x409)
        name.setName(full_name, 4, platform_id, plat_enc_id, 0x409)
        name.setName(ps_name, 6, platform_id, plat_enc_id, 0x409)
    name.setName(family, 16, 3, 1, 0x409)
    name.setName(subfamily, 17, 3, 1, 0x409)

    os2 = font["OS/2"]
    os2.usWeightClass = weight
    if weight >= 700:
        os2.fsSelection = (os2.fsSelection & ~0x40) | 0x20  # clear REGULAR, set BOLD
        font["head"].macStyle |= 0x01
    else:
        os2.fsSelection = (os2.fsSelection & ~0x20) | 0x40  # clear BOLD, set REGULAR
        font["head"].macStyle &= ~0x01
    os2.fsSelection &= ~0x01  # never italic


def _strip_variation_tables(font) -> None:
    for tag in ("fvar", "gvar", "avar", "HVAR", "MVAR", "cvar", "STAT"):
        if tag in font:
            del font[tag]


def load_static_inter(wght: int):
    """Fresh fully-static Inter face at *wght* (both axes pinned).  Not subset."""
    _subset, TTFont, instancer = _require_fonttools()
    var_font = TTFont(INTER_VF)
    location = {"wght": wght}
    if any(axis.axisTag == "opsz" for axis in var_font["fvar"].axes):
        location["opsz"] = OPSZ_PIN
    static = instancer.instantiateVariableFont(var_font, location, inplace=False, updateFontNames=True)
    _strip_variation_tables(static)
    return static


def build_inter_instances(
    char_set: Set[int], layout_features: Optional[Sequence[str]]
) -> List[Tuple[Path, bytes]]:
    """Instantiate + subset the four static Inter faces.  Returns ``[(path, bytes)]``."""
    if not INTER_VF.is_file():
        sys.exit(f"missing source font: {_rel(INTER_VF)}")

    results: List[Tuple[Path, bytes]] = []
    for subfamily, weight in INTER_INSTANCES:
        static = load_static_inter(weight)
        source_modified = static["head"].modified
        subset_font(static, char_set, layout_features)
        ps_name = f"Inter-{subfamily}"
        rename_face(static, "Inter", subfamily, ps_name, weight)
        static["head"].modified = source_modified  # deterministic output
        results.append((FONTS_DIR / f"{ps_name}.ttf", serialize(static)))
    return results


def build_lxgw(char_set: Set[int], layout_features: Optional[Sequence[str]]) -> Tuple[Path, bytes]:
    """Subset LXGW WenKai.  Returns ``(path, bytes)``."""
    _subset, TTFont, _instancer = _require_fonttools()
    if not LXGW_SRC.is_file():
        sys.exit(f"missing source font: {_rel(LXGW_SRC)}")

    font = TTFont(LXGW_SRC)
    modified = font["head"].modified
    subset_font(font, char_set, layout_features)
    # 改名的理由见 LXGW_SUBSET_FAMILY 的注释。
    rename_face(
        font,
        LXGW_SUBSET_FAMILY,
        "Regular",
        LXGW_SUBSET_PS_NAME,
        400,
    )
    font["head"].modified = modified
    return LXGW_OUT, serialize(font)


def probe_layout_features(
    loader: Callable[[], object], char_set: Set[int], mode: str
) -> Tuple[Optional[Sequence[str]], str]:
    """Decide between pyftsubset's default feature list and ``'*'``.

    Builds the face twice and keeps ``'*'`` only when it costs at most 10 % more
    bytes.  Returns ``(layout_features, rationale)``.
    """
    if mode == "default":
        return None, "forced: pyftsubset default (HarfBuzz-recommended) feature list"
    if mode == "all":
        return ["*"], "forced: --layout-features='*'"

    default_bytes = len(serialize(subset_font(loader(), char_set, None)))
    all_bytes = len(serialize(subset_font(loader(), char_set, ["*"])))
    ratio = all_bytes / max(default_bytes, 1)
    if ratio <= 1.10:
        return ["*"], (
            f"auto: '*' kept ({all_bytes:,} B vs {default_bytes:,} B default, "
            f"{ratio * 100 - 100:+.1f} %)"
        )
    return None, (
        f"auto: defaults kept ('*' would be {all_bytes:,} B vs {default_bytes:,} B, "
        f"{ratio * 100 - 100:+.1f} % — stylistic sets are dead weight here)"
    )


# --------------------------------------------------------------------------------------
# Verification
# --------------------------------------------------------------------------------------


@dataclass
class FontInfo:
    path: Path
    size: int
    codepoints: Set[int]
    glyph_count: int
    #: Code points whose glyph has a zero advance width (spaces, combining marks,
    #: format characters).  Used to flag characters that would render as nothing.
    zero_advance: Set[int]


def read_font_info(path: Path) -> FontInfo:
    _subset, TTFont, _instancer = _require_fonttools()
    font = TTFont(path, lazy=True)
    try:
        cmap = font.getBestCmap() or {}
        glyph_set = font.getGlyphSet()
        zero: Set[int] = set()
        for code_point, glyph_name in cmap.items():
            try:
                if glyph_set[glyph_name].width == 0:
                    zero.add(code_point)
            except KeyError:  # pragma: no cover - mapped glyph not in glyf
                pass
        return FontInfo(
            path=path,
            size=path.stat().st_size,
            codepoints=set(cmap),
            glyph_count=font["maxp"].numGlyphs,
            zero_advance=zero,
        )
    finally:
        font.close()


OUTPUT_FONTS: Tuple[Path, ...] = tuple(
    FONTS_DIR / f"Inter-{subfamily}.ttf" for subfamily, _w in INTER_INSTANCES
) + (LXGW_OUT,)


def verify(chars: CharSet, fonts: Sequence[FontInfo]) -> Tuple[List[int], List[str]]:
    """Check every collected code point against the union of the output cmaps."""
    union: Set[int] = set()
    for info in fonts:
        union |= info.codepoints

    missing = sorted(cp for cp in chars.codepoints if cp not in union)
    messages: List[str] = []
    if missing:
        messages.append(f"{len(missing)} collected code point(s) are in no output font:")
        for cp in missing[:100]:
            sources = ", ".join(chars.sources_of(cp)) or "<unknown>"
            messages.append(f"  U+{cp:04X}  {_display_char(cp)}  <- {sources}")
        if len(missing) > 100:
            messages.append(f"  ... and {len(missing) - 100} more")
    return missing, messages


def _display_char(cp: int) -> str:
    ch = chr(cp)
    if unicodedata.category(ch) in ("Cc", "Cf", "Zs") or ch == " ":
        return f"<{unicodedata.name(ch, 'unprintable')}>"
    return ch


# --------------------------------------------------------------------------------------
# Size reporting
# --------------------------------------------------------------------------------------


def _display_width(text: str) -> int:
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in text)


def _pad(text: str, width: int) -> str:
    return text + " " * max(0, width - _display_width(text))


def _human(num_bytes: int) -> str:
    return f"{num_bytes / 1024:,.1f} KiB"


@dataclass
class SizeRow:
    output: Path
    source: Path
    source_bytes: Optional[int]
    output_bytes: Optional[int]


def size_rows() -> List[SizeRow]:
    rows: List[SizeRow] = []
    for subfamily, _w in INTER_INSTANCES:
        out = FONTS_DIR / f"Inter-{subfamily}.ttf"
        rows.append(
            SizeRow(
                out,
                INTER_VF,
                INTER_VF.stat().st_size if INTER_VF.is_file() else None,
                out.stat().st_size if out.is_file() else None,
            )
        )
    rows.append(
        SizeRow(
            LXGW_OUT,
            LXGW_SRC,
            LXGW_SRC.stat().st_size if LXGW_SRC.is_file() else None,
            LXGW_OUT.stat().st_size if LXGW_OUT.is_file() else None,
        )
    )
    return rows


def print_size_table(rows: Sequence[SizeRow]) -> None:
    header = (
        _pad("Output file", 36)
        + _pad("Source file", 40)
        + _pad("Source", 14)
        + _pad("Output", 14)
        + "Reduction"
    )
    print(header)
    print("-" * _display_width(header))
    total_source = 0
    total_output = 0
    for row in rows:
        if row.source_bytes:
            total_source += row.source_bytes
        if row.output_bytes:
            total_output += row.output_bytes
        if row.source_bytes and row.output_bytes:
            pct = f"{(row.output_bytes - row.source_bytes) / row.source_bytes * 100:+.1f} %"
        else:
            pct = "n/a"
        print(
            _pad(_rel(row.output), 36)
            + _pad(_rel(row.source), 40)
            + _pad(_human(row.source_bytes) if row.source_bytes else "-", 14)
            + _pad(_human(row.output_bytes) if row.output_bytes else "-", 14)
            + pct
        )
    print("-" * _display_width(header))
    pct = f"{(total_output - total_source) / total_source * 100:+.1f} %" if total_source else "n/a"
    print(
        _pad(f"TOTAL ({len(rows)} faces)", 36)
        + _pad("", 40)
        + _pad(_human(total_source), 14)
        + _pad(_human(total_output), 14)
        + pct
    )
    inter_source = INTER_VF.stat().st_size if INTER_VF.is_file() else 0
    inter_output = sum(r.output_bytes or 0 for r in rows[:4])
    print(
        f"\n  Inter: 1 variable source ({inter_source:,} B) -> 4 static faces "
        f"({inter_output:,} B total, {inter_output / 4:,.0f} B each)"
    )
    print(
        "  Note: 'Source' is the upstream file in 指令/.  In the placeholder tree each "
        "shipped\n        font was a byte-for-byte copy of its source, so the reduction "
        "column is the\n        real before/after for this repository."
    )


# --------------------------------------------------------------------------------------
# Images (logo + PWA icons) — the `--images` extra
# --------------------------------------------------------------------------------------


@dataclass
class ImageRow:
    output: Path
    note: str
    before: Optional[int]
    after: Optional[int]


def build_images() -> List[ImageRow]:
    """Re-encode the logo losslessly and derive the favicon / PWA icons.

    Everything is driven from ``指令/instruction.png`` (186x230 RGBA, the source
    of truth), never from the already-optimised copy, so the operation is
    idempotent and cannot accumulate generation loss.
    """
    try:
        from PIL import Image
    except ImportError as exc:  # pragma: no cover
        sys.exit(f"Pillow is required for --images ({exc}); try: python -m pip install pillow")

    resample = Image.Resampling.LANCZOS
    rows: List[ImageRow] = []

    logo = Image.open(LOGO_PNG).convert("RGBA")
    logo.load()

    def record(path: Path, note: str, data: bytes, *, keep_smaller: bool) -> None:
        before = path.stat().st_size if path.is_file() else None
        if keep_smaller and before is not None and before <= len(data):
            rows.append(
                ImageRow(
                    path,
                    f"{note} — kept: re-encode is {len(data):,} B, not smaller than the "
                    f"{before:,} B already on disk",
                    before,
                    before,
                )
            )
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        rows.append(ImageRow(path, note, before, len(data)))

    # ---- 1. lossless PNG re-encode of the shipped asset --------------------
    buf = io.BytesIO()
    logo.save(buf, format="PNG", optimize=True, compress_level=9)
    png_bytes = buf.getvalue()

    # Prove losslessness *before* touching the asset.
    check = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    if check.size != logo.size or check.tobytes() != logo.tobytes():
        sys.exit("refusing to write assets/images/instruction.png: the re-encode is not lossless")

    record(
        IMAGES_DIR / "instruction.png",
        "lossless PNG re-encode (optimize=True, RGBA, 186x230)",
        png_bytes,
        keep_smaller=True,
    )

    # ---- 2. lossless WebP sibling (kept only when meaningfully smaller) ----
    # NOTE: written to docs/images/, NOT assets/images/.  `pubspec.yaml` declares
    # the whole `assets/images/` directory, so anything dropped in there is
    # bundled into every build — and nothing in Dart references this file.
    # It exists purely as evidence for the "could we ship WebP?" question.
    webp_buf = io.BytesIO()
    logo.save(webp_buf, format="WEBP", lossless=True, quality=100, method=6)
    webp_bytes = webp_buf.getvalue()
    webp_path = REPO_ROOT / "docs" / "images" / "instruction.webp"
    webp_path.parent.mkdir(parents=True, exist_ok=True)
    if len(webp_bytes) <= int(len(png_bytes) * 0.95):
        record(
            webp_path,
            "lossless WebP sibling (not referenced from Dart)",
            webp_bytes,
            keep_smaller=False,
        )
    else:
        if webp_path.is_file():
            webp_path.unlink()
        rows.append(
            ImageRow(
                webp_path,
                f"skipped — lossless WebP is {len(webp_bytes):,} B vs {len(png_bytes):,} B "
                "PNG, not meaningfully smaller",
                None,
                None,
            )
        )

    # ---- 3. square icons ---------------------------------------------------
    def square(
        size: int,
        content_ratio: float,
        *,
        opaque_black: bool,
    ) -> bytes:
        """Centre the artwork on a square canvas; return the PNG bytes.

        ``opaque_black`` drops the alpha channel entirely (lossless here — the
        canvas is uniformly opaque), which also makes the maskable icons
        genuinely opaque for Android's mask.
        """
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 255) if opaque_black else (0, 0, 0, 0))
        box = max(1, int(round(size * content_ratio)))
        w, h = logo.size
        scale = min(box / w, box / h)
        thumb = logo.resize((max(1, round(w * scale)), max(1, round(h * scale))), resample)
        canvas.alpha_composite(thumb, ((size - thumb.width) // 2, (size - thumb.height) // 2))
        result = canvas.convert("RGB") if opaque_black else canvas
        out = io.BytesIO()
        result.save(out, format="PNG", optimize=True, compress_level=9)
        return out.getvalue()

    # Maskable: 20 % padding per side -> artwork inside the middle 60 %.  For this
    # 186x230 artwork the corners then sit ~0.386 * size from the centre, which is
    # inside Android's 0.4 * size safe circle.
    record(
        WEB_DIR / "favicon.png",
        "32x32 RGBA favicon (transparent)",
        square(32, 0.92, opaque_black=False),
        keep_smaller=False,
    )
    record(
        WEB_DIR / "icons" / "Icon-192.png",
        "192x192 RGB app icon (black canvas)",
        square(192, 0.82, opaque_black=True),
        keep_smaller=False,
    )
    record(
        WEB_DIR / "icons" / "Icon-512.png",
        "512x512 RGB app icon (black canvas)",
        square(512, 0.82, opaque_black=True),
        keep_smaller=False,
    )
    record(
        WEB_DIR / "icons" / "Icon-maskable-192.png",
        "192x192 RGB maskable icon (20 % safe padding)",
        square(192, 0.60, opaque_black=True),
        keep_smaller=False,
    )
    record(
        WEB_DIR / "icons" / "Icon-maskable-512.png",
        "512x512 RGB maskable icon (20 % safe padding)",
        square(512, 0.60, opaque_black=True),
        keep_smaller=False,
    )

    # ---- 4. Windows 桌面图标 ------------------------------------------------
    # 本地桌面是主要目标，任务栏/资源管理器里不该是 Flutter 的默认图标。
    # 源图只有 186x230，所以最大只做到 128，再往上就是放大糊图了。
    ico_sizes = (16, 24, 32, 48, 64, 128)
    ico_images = []
    for size in ico_sizes:
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        box = max(1, int(round(size * 0.86)))
        w, h = logo.size
        scale = min(box / w, box / h)
        thumb = logo.resize(
            (max(1, round(w * scale)), max(1, round(h * scale))),
            resample,
        )
        canvas.alpha_composite(
            thumb,
            ((size - thumb.width) // 2, (size - thumb.height) // 2),
        )
        ico_images.append(canvas)
    ico_buf = io.BytesIO()
    ico_images[-1].save(
        ico_buf,
        format="ICO",
        sizes=[(s, s) for s in ico_sizes],
        append_images=ico_images[:-1],
    )
    record(
        WINDOWS_ICON,
        "Windows app icon (.ico, 16-128 px, transparent)",
        ico_buf.getvalue(),
        keep_smaller=False,
    )
    return rows


def print_image_table(rows: Sequence[ImageRow]) -> None:
    header = _pad("Image", 40) + _pad("Before", 14) + _pad("After", 14) + "Note"
    print(header)
    print("-" * _display_width(header))
    for row in rows:
        print(
            _pad(_rel(row.output), 40)
            + _pad(_human(row.before) if row.before else "-", 14)
            + _pad(_human(row.after) if row.after else "-", 14)
            + row.note
        )


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="subset_fonts.py",
        description="Regenerate the five subsetted app fonts (and, with --images, the PWA icons).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "examples:\n"
            "  python tools/subset_fonts.py            rebuild + report + verify\n"
            "  python tools/subset_fonts.py --verify   verification only (CI acceptance test)\n"
            "  python tools/subset_fonts.py --report   size table only\n"
            "  python tools/subset_fonts.py --images   also regenerate web/favicon.png + web/icons/*\n"
        ),
    )
    parser.add_argument("--verify", action="store_true", help="verify only; exit non-zero if a code point is missing")
    parser.add_argument("--report", action="store_true", help="print the size table only")
    parser.add_argument("--images", action="store_true", help="also (re)generate the logo asset and PWA icons")
    parser.add_argument("--no-verify", action="store_true", help="skip the automatic verification after a build")
    parser.add_argument(
        "--layout-features",
        choices=("auto", "default", "all"),
        default="auto",
        help="OpenType feature retention: auto (probe, default), default (pyftsubset list), all ('*')",
    )
    args = parser.parse_args(argv)

    build = not (args.verify or args.report)

    print("Collecting the required character set …")
    warnings: List[str] = []
    chars, scramble_glyphs = collect_characters(warnings)
    inter_set, lxgw_set = build_subsets(chars, scramble_glyphs)

    cjk_count = sum(1 for cp in chars.codepoints if is_cjk(cp))
    print(
        f"  -> {len(chars)} unique code points "
        f"({cjk_count} CJK / fullwidth, {len(chars) - cjk_count} Latin, symbol, punctuation)"
    )
    if chars.skipped:
        names = ", ".join(f"U+{cp:04X}" for cp in sorted(chars.skipped)[:8])
        print(f"  -> ignored {len(chars.skipped)} non-renderable control/format code point(s): {names}")
    print(
        f"  -> requested from Inter: {len(inter_set)} code points; "
        f"from LXGW WenKai: {len(lxgw_set)} code points"
    )
    for warning in warnings:
        print(f"  ! {warning}")

    if build:
        _require_fonttools()
        FONTS_DIR.mkdir(parents=True, exist_ok=True)

        print("\nChoosing OpenType layout features …")
        inter_features, inter_reason = probe_layout_features(
            lambda: load_static_inter(400), inter_set, args.layout_features
        )
        print(f"  Inter : {inter_reason}")
        lxgw_features, lxgw_reason = probe_layout_features(
            lambda: _require_fonttools()[1](LXGW_SRC), lxgw_set, args.layout_features
        )
        print(f"  LXGW  : {lxgw_reason}")

        print("\nBuilding static Inter instances (wght 400/500/600/700, opsz pinned to 14.0) …")
        for path, data in build_inter_instances(inter_set, inter_features):
            path.write_bytes(data)
            print(f"  wrote {_rel(path):<38} {len(data):>10,} B")

        print("\nSubsetting LXGW WenKai …")
        path, data = build_lxgw(lxgw_set, lxgw_features)
        path.write_bytes(data)
        print(f"  wrote {_rel(path):<38} {len(data):>10,} B")

        print()
        print_size_table(size_rows())

    if args.images:
        if build:
            print()
        print("\nRegenerating images …")
        print_image_table(build_images())

    if args.report and not build:
        print()
        print_size_table(size_rows())

    if args.verify or (build and not args.no_verify):
        print("\nVerifying every collected code point against the five output fonts …")
        missing_outputs = [p for p in OUTPUT_FONTS if not p.is_file()]
        if missing_outputs:
            for path in missing_outputs:
                print(f"  ! missing output font: {_rel(path)}")
            print("\nFAIL — run `python tools/subset_fonts.py` first.")
            return 2

        fonts = [read_font_info(p) for p in OUTPUT_FONTS]
        for info in fonts:
            print(
                f"  {_rel(info.path):<38} {info.size:>10,} B  "
                f"{len(info.codepoints):>6} cmap entries  {info.glyph_count:>6} glyphs"
            )
        missing, messages = verify(chars, fonts)
        for message in messages:
            print(message)
        if missing:
            print(f"\nFAIL — {len(missing)} collected code point(s) are missing from all five fonts.")
            return 1
        print(f"\nOK — all {len(chars)} collected code points are covered by the output fonts.")
        # Extra smoke test: a collected character mapped to a zero-width glyph
        # would render as nothing even though its cmap entry exists.
        for info in fonts:
            hollow = sorted(
                cp
                for cp in info.zero_advance & chars.codepoints
                if unicodedata.category(chr(cp)) not in ("Zs", "Cc", "Cf")
            )
            if hollow:
                names = ", ".join(f"U+{cp:04X}" for cp in hollow[:10])
                print(f"  ! {_rel(info.path)} maps {len(hollow)} collected character(s) to zero-advance glyphs: {names}")

    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):  # pragma: no cover
        pass
    raise SystemExit(main())
