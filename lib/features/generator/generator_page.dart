import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/neon_button.dart';
import '../../data/models/instruction.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_scope.dart';
import 'widgets/scramble_text.dart';

/// 原版 `index.html` 的 1:1 复刻。
///
/// 对应关系：
/// * `.image-header > img`   → [_HeaderImage]（`margin-top:40px`，宽 = min(50vw,600px) × 30%）
/// * `#display-container`    → [_DisplayContainer]（`margin:40px 0 60px`、`min-height:100px`、
///   `max-width:900px`、`padding:0 20px`、`font-size:24px`、`letter-spacing:2px`、三层发光）
/// * `button#trigger-btn`    → [NeonButton]（`margin-top:30px`）
/// * `.footer-note`          → [_FooterNote]（`position:fixed; bottom:20px`）
///
/// 原版没有历史、收藏、导航、计数器——这里也没有。
class GeneratorPage extends StatefulWidget {
  const GeneratorPage({super.key});

  @override
  State<GeneratorPage> createState() => _GeneratorPageState();
}

class _GeneratorPageState extends State<GeneratorPage> {
  /// 对应原版脚本里的 `isRunning`：动画播放期间点击按钮会被直接忽略。
  bool _isRunning = false;

  void _trigger() {
    // 原版：`if (isRunning) return;`
    if (_isRunning) {
      return;
    }
    final controllers = AppScope.of(context);
    setState(() => _isRunning = true);
    controllers.prescriptions.generate();
  }

  void _onAnimationCompleted() {
    if (mounted && _isRunning) {
      setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controllers = AppScope.of(context);
    final l10n = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: controllers.prescriptions,
      builder: (context, _) {
        final settings = controllers.settings.value;
        final instruction = controllers.prescriptions.current;
        // 设置里的「减少动效」与系统无障碍开关，任一为真就立即显示最终文本。
        final animate = !(settings.reduceMotion ||
            context.systemDisablesAnimations);

        return Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  // 对应 `body { align-items:center; justify-content:flex-start }`
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    // `.image-header { margin-top: 40px }`
                    const SizedBox(height: 40),
                    const _HeaderImage(),
                    // CSS 里 `<img>` 是 inline 元素，行盒在基线下方还留着
                    // strut 的降部空间：Chrome 实测 `.image-header` 高
                    // 226.58px = 图 222.58px + 4px。少了这 4px，logo 以下的
                    // 所有内容都会整体上移。
                    const SizedBox(height: 4),
                    // `#display-container { margin-top: 40px }`
                    const SizedBox(height: 40),
                    _DisplayContainer(
                      instruction: instruction,
                      prefix: l10n.instructionPrefix,
                      animate: animate,
                      animationSpeed: settings.animationSpeed,
                      animationTick: controllers.prescriptions.generationTick,
                      onCompleted: _onAnimationCompleted,
                    ),
                    // `#display-container { margin-bottom: 60px }`
                    const SizedBox(height: 60),
                    // `button { margin-top: 30px }`
                    const SizedBox(height: 30),
                    NeonButton(
                      label: l10n.generateButton,
                      onPressed: _trigger,
                    ),
                  ],
                ),
              ),
            ),
            const _FooterNote(),
          ],
        );
      },
    );
  }
}

/// `.image-header { width:50%; max-width:600px; margin-top:40px; text-align:center }`
/// 配合 `img { width:30%; height:auto; border-radius:8px }`。
class _HeaderImage extends StatelessWidget {
  const _HeaderImage();

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    // 容器宽 = min(50% 视口, 600px)，图片宽 = 容器宽 × 30%（最大 180px）。
    final imageWidth = (viewportWidth * 0.5).clamp(0.0, 600.0) * 0.3;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/images/instruction.png',
        width: imageWidth,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: AppLocalizations.of(context).appTitle,
      ),
    );
  }
}

/// `#display-container`。
///
/// 原版首次点击之前这里是空 div（靠 `min-height:100px` 占位），
/// 因此在生成第一条指令前不渲染任何文本。
class _DisplayContainer extends StatefulWidget {
  const _DisplayContainer({
    required this.instruction,
    required this.prefix,
    required this.animate,
    required this.animationSpeed,
    required this.animationTick,
    required this.onCompleted,
  });

  final Instruction? instruction;
  final String prefix;
  final bool animate;
  final double animationSpeed;
  final int animationTick;
  final VoidCallback onCompleted;

  @override
  State<_DisplayContainer> createState() => _DisplayContainerState();
}

class _DisplayContainerState extends State<_DisplayContainer> {
  /// 原版 `startScrambleAnimation`：每 5 帧 `iteration += length > 20 ? 1 : 0.6`，
  /// 在 60fps 下即**长句 12 字/秒、短句 7.2 字/秒**。
  ///
  /// （原版按帧计数，在 120Hz 屏幕上会快一倍；这里按时间计，60Hz 下完全一致。）
  double get _charsPerSecond {
    final length =
        (widget.instruction?.body.length ?? 0) + widget.prefix.length;
    return (length > 20 ? 12.0 : 7.2) * widget.animationSpeed;
  }

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    final current = widget.instruction;
    final text = current == null ? null : '${widget.prefix}${current.body}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 100, maxWidth: 900),
        child: text == null
            ? const SizedBox(width: double.infinity)
            : RepaintBoundary(
                child: ScrambleText(
                  key: ValueKey<int>(widget.animationTick),
                  text: text,
                  textAlign: TextAlign.center,
                  animate: widget.animate,
                  charsPerSecond: _charsPerSecond,
                  // 原版没有最短/最长时长限制，这里把区间放开到不生效。
                  minDuration: Duration.zero,
                  maxDuration: const Duration(days: 1),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    // 原版没有写 line-height，用的是字体自身的 normal 行距。
                    // Chrome 实测霞鹜文楷在 24px 下行距为 32px，这里显式锁成
                    // 同样的 4/3，避免两端的字体度量差异导致换行行数不同。
                    height: 4 / 3,
                    color: neon.textPrimary,
                    // 动画期间与播完之后用**同一套**三层辉光：底座 Text 被
                    // ScrambleText 缓存成图层，逐帧重绘的只有乱码字形，因此
                    // 这里不需要为了性能削层数（削了会看到「锁定过程中发光变弱」）。
                    shadows: neon.glowShadows(),
                  ),
                  semanticLabel: text,
                  onCompleted: widget.onCompleted,
                ),
              ),
      ),
    );
  }
}

/// `.footer-note`：`position:fixed; bottom:20px; font-size:12px;
/// letter-spacing:2px; text-shadow: 0 0 5px var(--neon-blue)`。
///
/// 原版只有一行「警告」；下面那行免责声明是本项目加的第二行（同人二创需要
/// 说明「内容纯属虚构」），样式更弱以免抢走原版警告的注意力。
///
/// 原版没有左右内边距、也没有安全区处理，换行点就是视口宽度——这里保持一致
/// （多留边距会让窄屏下的换行位置与原版不同）。
class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            l10n.footerWarning,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 2,
              color: neon.textPrimary,
              shadows: neon.softGlow,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.footerDisclaimer,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1,
              color: neon.textMuted,
              shadows: neon.faintGlow,
            ),
          ),
        ],
      ),
    );
  }
}
