import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// `获取指令` 按钮，逐条对应原版 `main.css`：
///
/// ```css
/// button {
///     margin-top: 30px; padding: 15px 20px; font-size: 14px;
///     background: transparent; color: var(--bright-white); border: 0px;
///     cursor: pointer; transition: all 0.3s ease;
///     text-transform: uppercase; letter-spacing: 4px;
///     text-shadow: 0 0 5px var(--neon-blue);
///     font-family: 'Inter', 'LXGWWenKai', sans-serif;
/// }
/// button:hover {
///     background: var(--bright-white); color: var(--dark-bg);
///     box-shadow: 0 0 30px var(--neon-blue); font-weight: bold;
/// }
/// ```
///
/// `margin-top: 30px` 由父级 `Column` 的 `SizedBox` 承担，不在按钮内部实现。
///
/// 两个容易漏掉的原生行为也在这里补齐：
/// * 原版是真正的 `<button>`，**Tab 聚焦后 Enter / Space 可以触发**；
/// * `transition: all` 会把 `color` 与 `font-weight` 一起做 300ms 过渡，
///   不只是背景与阴影。
class NeonButton extends StatefulWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  final String label;

  /// 原版在动画播放期间直接 `return` 忽略点击，因此这里始终可点，
  /// 「忽略」的逻辑由调用方决定，悬停高亮不受影响。
  final VoidCallback onPressed;

  final bool autofocus;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    // CSS 的 :hover 只对指针生效；键盘聚焦时给一个同样明显的反馈
    // （原版聚焦时由浏览器画焦点环，同属「可见的聚焦指示」）。
    final active = _hovered || _focused;

    const transition = Duration(milliseconds: 300);

    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: FocusableActionDetector(
          autofocus: widget.autofocus,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (intent) {
                widget.onPressed();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: widget.onPressed,
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            child: AnimatedContainer(
              duration: transition,
              curve: Curves.ease,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 15,
              ),
              decoration: BoxDecoration(
                color: active ? neon.textPrimary : Colors.transparent,
                // 圆角是本项目相对原版的一处**有意**改动（原版 `border: 0`、
                // 无圆角）：0 圆角的实心白块在悬停时过于生硬。
                borderRadius: BorderRadius.circular(8),
                // ⚠️ 这里必须始终给出**等长**的阴影列表，靠颜色淡出，不能在
                // `null` 与列表之间切换：`BoxShadow.lerpList` 对多出来的那一项
                // 调用 `scale(t)`，t=1 时等于原样保留 —— 结果是第一次悬停之后
                // 那圈 accent 发光永远不消失（截图上表现为按钮一直亮着一块）。
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: active ? neon.accent : const Color(0x00000000),
                    blurRadius: cssBlurToFlutter(30),
                  ),
                ],
              ),
              child: ExcludeSemantics(
                // `AnimatedDefaultTextStyle` 对应 CSS 的 `transition: all`：
                // 文字颜色与字重也跟着 300ms 过渡，不会在悬停首帧出现
                // 「黑字压黑底」的闪烁。
                child: AnimatedDefaultTextStyle(
                  duration: transition,
                  curve: Curves.ease,
                  style: TextStyle(
                    fontFamily: kLatinFontFamily,
                    fontFamilyFallback: kFontFallback,
                    fontSize: 14,
                    letterSpacing: 4,
                    color: active ? neon.background : neon.textPrimary,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    // 原版按钮的 text-shadow 只有一层，且 `:hover` 不覆盖它 ——
                    // 两态等长且恒定，不存在上面那种 lerp 残留问题。
                    shadows: <Shadow>[
                      Shadow(
                        color: neon.accent,
                        blurRadius: cssBlurToFlutter(5),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.label.toUpperCase(),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
