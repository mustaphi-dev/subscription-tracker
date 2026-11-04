import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:sprung/sprung.dart';

import 'brands.dart';
import 'data.dart';

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

extension SourceLook on PaymentSource {
  /// Bank name to show: the provider's, or whatever the user typed for other banks.
  String get bank => providerLabels[provider] ?? institution ?? 'Bank';
  Color get color => providerColors[provider] ?? HSLColor.fromAHSL(1, (bank.toLowerCase().hashCode % 360).abs().toDouble(), 0.55, 0.6).toColor();
}

final springOut = Sprung.overDamped;
final springBounce = Sprung.underDamped;
const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  final text = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: kText, displayColor: kText);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    // Monochrome so Material widgets (date picker, cursors, selection, switches) match the white buttons
    // instead of Material 3's default purple tones.
    colorScheme: const ColorScheme.dark(
      primary: kText,
      onPrimary: kBg,
      secondary: kText,
      onSecondary: kBg,
      surface: kSurface,
      onSurface: kText,
      surfaceContainerHigh: kSurfaceHi,
      surfaceTint: Colors.transparent,
      outline: kFaint,
      outlineVariant: kLine,
      error: kCrimson,
    ),
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: kLine,
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kMint : kSurfaceHi),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
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
  const MerchantAvatar(this.name, {super.key, this.size = 40, this.dot});
  final String name;
  final double size;
  final Color? dot;
  @override
  Widget build(BuildContext context) {
    final hue = (name.toLowerCase().hashCode % 360).abs().toDouble();
    final c = HSLColor.fromAHSL(1, hue, 0.45, 0.52).toColor();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        LogoTile(
          name,
          size: size,
          radius: size * 0.32,
          fallback: Container(
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
        ),
        if (dot != null)
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: BoxDecoration(
                color: dot,
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
/// Success toasts also close any open bottom sheet (the action is done); errors pass
/// [closeSheets] false so the user can fix their input.
void showToast(BuildContext context, String message,
    {Color tone = kText, IconData icon = Icons.check_circle_rounded, Duration duration = const Duration(milliseconds: 2600), bool closeSheets = true}) {
  _toastTimer?.cancel();
  _toast?.remove();
  final overlay = Overlay.of(context, rootOverlay: true);
  if (closeSheets) Navigator.of(context, rootNavigator: true).popUntil((r) => r is! ModalBottomSheetRoute);
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
    showToast(context, message, tone: kCrimson, icon: Icons.error_rounded, duration: const Duration(seconds: 4), closeSheets: false);

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

// ───────── Select drawer ─────────

/// One choice in [pickFromSheet]: value, label, optional subtitle.
typedef SelectOption<T> = (T value, String label, String? sub);

/// Bottom-sheet list picker with a check on the current value. Returns the picked value, or null if dismissed.
Future<T?> pickFromSheet<T>(BuildContext context, {required String title, required List<SelectOption<T>> options, T? selected}) =>
    showSheet<T>(
      context,
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 12), child: Text(title, style: display(20))),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: [
              for (final (value, label, sub) in options)
                Builder(
                  builder: (ctx) => Pressable(
                    scale: 0.98,
                    onTap: () => Navigator.pop(ctx, value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: value == selected ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            if (sub != null) Text(sub, style: caption),
                          ]),
                        ),
                        if (value == selected) const Icon(Icons.check_rounded, color: kMint, size: 20),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );

/// Form field that shows the current choice and opens [pickFromSheet].
class SelectField<T> extends StatelessWidget {
  const SelectField({super.key, required this.title, required this.options, required this.value, required this.onChanged, this.hint});
  final String title;
  final List<SelectOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final current = options.where((o) => o.$1 == value).firstOrNull?.$2;
    return Semantics(
      button: true,
      label: '$title: ${current ?? hint ?? ''}',
      child: Pressable(
        scale: 0.98,
        onTap: () async {
          final v = await pickFromSheet<T>(context, title: title, options: options, selected: value);
          if (v != null) onChanged(v);
        },
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: kSurfaceHi, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(
              child: Text(current ?? hint ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: current == null ? kMuted : kText)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.unfold_more_rounded, size: 18, color: kMuted),
          ]),
        ),
      ),
    );
  }
}

const currencyNames = {
  'GBP': 'British pound', 'USD': 'US dollar', 'EUR': 'Euro', 'GHS': 'Ghanaian cedi', 'NGN': 'Nigerian naira',
  'KES': 'Kenyan shilling', 'ZAR': 'South African rand', 'CAD': 'Canadian dollar', 'AUD': 'Australian dollar',
  'CHF': 'Swiss franc', 'JPY': 'Japanese yen', 'INR': 'Indian rupee', 'AED': 'UAE dirham',
};

List<SelectOption<String>> currencyOptions(Iterable<String> codes) => [for (final c in codes) (c, c, currencyNames[c])];

// ───────── Currency picker ─────────

const currencies = [
  ('GBP', '🇬🇧', 'British pound'),
  ('USD', '🇺🇸', 'US dollar'),
  ('EUR', '🇪🇺', 'Euro'),
  ('GHS', '🇬🇭', 'Ghanaian cedi'),
];

/// Custom popover that springs out of its top-right corner, just under the top bar.
/// Opens with a spring; closes fast (showGeneralDialog can't have a shorter reverse duration).
Future<String?> pickCurrency(BuildContext context, String current) => Navigator.of(context, rootNavigator: true).push<String>(PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, _, _) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(top: MediaQuery.of(ctx).padding.top + 52, right: 12),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 248,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: kSurfaceHi,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: kLine),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 32, offset: Offset(0, 12))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Text('DISPLAY CURRENCY', style: TextStyle(color: kFaint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                ),
                for (final (code, flag, name) in currencies)
                  Pressable(
                    scale: 0.98,
                    onTap: () => Navigator.pop(ctx, code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: code == current ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(children: [
                        Text(flag, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(code, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(name, style: caption),
                          ]),
                        ),
                        AnimatedOpacity(
                          opacity: code == current ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: const Icon(Icons.check_rounded, color: kMint, size: 20),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: const Interval(0, 0.5), reverseCurve: Curves.easeIn),
        child: ScaleTransition(
          alignment: Alignment.topRight,
          scale: Tween(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: a, curve: springBounce, reverseCurve: Curves.easeIn)),
          child: child,
        ),
      ),
    ));

/// Pill that shows the base currency and opens [pickCurrency].
class CurrencyPill extends StatelessWidget {
  const CurrencyPill({super.key, required this.current, required this.onChanged});
  final String current;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final flag = currencies.where((c) => c.$1 == current).firstOrNull?.$2 ?? '💱';
    return Semantics(
      button: true,
      label: 'Display currency $current',
      child: Pressable(
        onTap: () async {
          final picked = await pickCurrency(context, current);
          if (picked != null && picked != current) onChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18), border: Border.all(color: kLine)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(flag, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(current, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(width: 2),
            const Icon(Icons.unfold_more_rounded, size: 16, color: kMuted),
          ]),
        ),
      ),
    );
  }
}

/// Signed-in user's initial on the brand gradient.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) {
    final email = db.auth.currentUser?.email ?? '';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kAccent, Color(0xFF3D7BFF)])),
      child: email.isEmpty
          ? Icon(Icons.person_rounded, size: size * 0.55)
          : Text(email[0].toUpperCase(), style: display(size * 0.45, weight: FontWeight.w700)),
    );
  }
}
