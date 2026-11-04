import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:sprung/sprung.dart';

// ───────── Tokens ─────────
// Content lives on solid layered surfaces; glass is reserved for floating chrome.
const kBg = Color(0xFF07080C);
const kSurface = Color(0xFF111318);
const kSurfaceHi = Color(0xFF191C23);
const kLine = Color(0x14FFFFFF);
const kText = Color(0xFFF4F5F7);
const kMuted = Color(0xFF8B909C);
const kFaint = Color(0xFF545966);
const kAccent = Color(0xFF8B7CFF);
const kMint = Color(0xFF34D399);
const kAmber = Color(0xFFFFB547);
const kCrimson = Color(0xFFFF5C6C);

const providerColors = {
  'revolut': Color(0xFF3D7BFF),
  'wise': Color(0xFF9FE870),
  'lloyds': Color(0xFF00A56A),
  'paypal': Color(0xFF6C63FF),
};
const providerLabels = {'revolut': 'Revolut', 'wise': 'Wise', 'lloyds': 'Lloyds', 'paypal': 'PayPal'};

final springOut = Sprung.overDamped;
final springBounce = Sprung.underDamped;
const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  final text = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: kText, displayColor: kText);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: base.colorScheme.copyWith(primary: kAccent, surface: kSurface, onSurface: kText),
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: kLine,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kText,
        foregroundColor: kBg,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kText,
        minimumSize: const Size.fromHeight(44),
        side: const BorderSide(color: kLine),
        shape: const StadiumBorder(),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: kSurfaceHi,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
      labelStyle: TextStyle(color: kMuted),
    ),
  );
}

TextStyle display(double size, {Color color = kText, FontWeight weight = FontWeight.w700}) =>
    GoogleFonts.interTight(fontSize: size, fontWeight: weight, color: color, letterSpacing: -size * 0.03, fontFeatures: tabular);

const label = TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w500);
const caption = TextStyle(color: kMuted, fontSize: 12);

String money(num amount, String ccy) => NumberFormat.simpleCurrency(locale: 'en_GB', name: ccy).format(amount);

String compactMoney(num amount, String ccy) =>
    NumberFormat.compactSimpleCurrency(locale: 'en_GB', name: ccy, decimalDigits: amount.abs() < 1000 ? 0 : 1).format(amount);

/// `GH₵ 250.00 · ≈ £12.40`, or just `£12.40` when already in base.
String dualMoney(num amount, String ccy, num? baseAmount, String base) =>
    ccy == base || baseAmount == null ? money(amount, ccy) : '${money(amount, ccy)} · ≈ ${money(baseAmount, base)}';

// ───────── Money ─────────

/// Revolut-style figure: large whole part, small raised decimals, animated between values.
class BigMoney extends StatelessWidget {
  const BigMoney(this.value, this.ccy, {super.key, this.size = 48, this.color = kText});
  final double value;
  final String ccy;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: value),
        duration: const Duration(milliseconds: 900),
        curve: springOut,
        builder: (_, v, _) {
          final s = money(v, ccy);
          final dot = s.lastIndexOf('.');
          return Text.rich(
            TextSpan(children: [
              TextSpan(text: dot < 0 ? s : s.substring(0, dot), style: display(size, color: color)),
              if (dot >= 0)
                TextSpan(text: s.substring(dot), style: display(size * 0.5, color: color.withValues(alpha: 0.55))),
            ]),
          );
        },
      );
}

// ───────── Surfaces ─────────

/// Solid content surface. The default container for everything that isn't floating chrome.
class Surface extends StatelessWidget {
  const Surface({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = kSurface, this.radius = 22, this.onTap, this.border});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final VoidCallback? onTap;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? kLine),
      ),
      child: child,
    );
    return onTap == null ? box : Pressable(onTap: onTap!, child: box);
  }
}

/// Scale-down on press with a light haptic. Used for every tappable surface.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.scale = 0.97});
  final Widget child;
  final VoidCallback onTap;
  final double scale;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 220),
          curve: springBounce,
          child: widget.child,
        ),
      );
}

/// Real refractive Liquid Glass (Impeller). Falls back to the package's FakeGlass where
/// shader filters aren't available (Skia / some emulators).
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 28, this.oval = false, this.tint = const Color(0x1AFFFFFF)});
  final Widget child;
  final double radius;
  final bool oval;
  final Color tint;

  @override
  Widget build(BuildContext context) => LiquidGlass.withOwnLayer(
        fake: !ImageFilter.isShaderFilterSupported,
        settings: LiquidGlassSettings(
          thickness: 18,
          blur: 6,
          glassColor: tint,
          lightIntensity: 0.7,
          saturation: 1.6,
          refractiveIndex: 1.25,
        ),
        shape: oval ? const LiquidOval() : LiquidRoundedSuperellipse(borderRadius: radius),
        glassContainsChild: false,
        child: child,
      );
}

/// Single soft glow behind the top of a screen, tinted by context.
class Ambient extends StatelessWidget {
  const Ambient({super.key, required this.child, this.color = kAccent});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Stack(children: [
        const Positioned.fill(child: ColoredBox(color: kBg)),
        Positioned(
          top: -220,
          left: -120,
          right: -120,
          height: 560,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ]);
}

/// Sliding segmented control (one solid track, one moving thumb).
class Segmented extends StatelessWidget {
  const Segmented({super.key, required this.labels, required this.selected, required this.onSelect});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
        child: LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth / labels.length;
          return Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 380),
              curve: springBounce,
              left: w * selected,
              width: w,
              top: 0,
              bottom: 0,
              child: DecoratedBox(decoration: BoxDecoration(color: kSurfaceHi, borderRadius: BorderRadius.circular(16))),
            ),
            Row(children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelect(i);
                    },
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: i == selected ? kText : kMuted),
                        child: Text(labels[i], maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                      ),
                    ),
                  ),
                ),
            ]),
          ]);
        }),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(),
          ?trailing,
        ]),
      );
}

class MerchantAvatar extends StatelessWidget {
  const MerchantAvatar(this.name, {super.key, this.size = 40, this.provider});
  final String name;
  final double size;
  final String? provider;
  @override
  Widget build(BuildContext context) {
    final hue = (name.toLowerCase().hashCode % 360).abs().toDouble();
    final c = HSLColor.fromAHSL(1, hue, 0.45, 0.52).toColor();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.32),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c, Color.lerp(c, kBg, 0.45)!]),
          ),
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.42, color: Colors.white)),
        ),
        if (provider != null)
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: BoxDecoration(
                color: providerColors[provider],
                shape: BoxShape.circle,
                border: Border.all(color: kSurface, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

// ───────── Toast ─────────

OverlayEntry? _toast;
Timer? _toastTimer;

/// Top toast: auto-dismisses after [duration], swipe up to dismiss early. Replaces lingering snackbars.
void showToast(BuildContext context, String message, {Color tone = kText, IconData icon = Icons.check_circle_rounded, Duration duration = const Duration(milliseconds: 2600)}) {
  _toastTimer?.cancel();
  _toast?.remove();
  final overlay = Overlay.of(context, rootOverlay: true);
  final visible = ValueNotifier(false);
  void close() {
    visible.value = false;
    _toastTimer = Timer(const Duration(milliseconds: 300), () {
      _toast?.remove();
      _toast = null;
    });
  }

  _toast = OverlayEntry(
    builder: (ctx) => Positioned(
      top: MediaQuery.of(ctx).padding.top + 8,
      left: 16,
      right: 16,
      child: ValueListenableBuilder(
        valueListenable: visible,
        builder: (_, v, child) => AnimatedSlide(
          offset: v ? Offset.zero : const Offset(0, -1.4),
          duration: const Duration(milliseconds: 420),
          curve: springBounce,
          child: AnimatedOpacity(opacity: v ? 1 : 0, duration: const Duration(milliseconds: 200), child: child),
        ),
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < 0) close();
          },
          onTap: close,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: kSurfaceHi,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kLine),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: Row(children: [
                Icon(icon, color: tone, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(message, style: const TextStyle(fontSize: 14, height: 1.3))),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(_toast!);
  HapticFeedback.lightImpact();
  WidgetsBinding.instance.addPostFrameCallback((_) => visible.value = true);
  _toastTimer = Timer(duration, close);
}

void showError(BuildContext context, String message) =>
    showToast(context, message, tone: kCrimson, icon: Icons.error_rounded, duration: const Duration(seconds: 4));

/// Solid bottom sheet with a grab handle.
Future<T?> showSheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: kFaint, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Flexible(child: child),
          ]),
        ),
      ),
    );
