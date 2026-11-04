import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'ui.dart';

const _storage = FlutterSecureStorage();
const _pinLength = 6;
const lockTimeout = Duration(seconds: 15);

/// Salted SHA-256 PIN in Keychain / Keystore. Never leaves the device.
class PinStore {
  static Future<bool> hasPin() async => await _storage.read(key: 'pin_hash') != null;

  static String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  static Future<void> setPin(String pin) async {
    final salt = base64Url.encode(List.generate(16, (_) => Random.secure().nextInt(256)));
    await _storage.write(key: 'pin_salt', value: salt);
    await _storage.write(key: 'pin_hash', value: _hash(pin, salt));
    await _storage.delete(key: 'pin_fails');
  }

  /// Returns null on success, else seconds to wait (0 = just wrong).
  static Future<int?> verify(String pin) async {
    final fails = int.parse(await _storage.read(key: 'pin_fails') ?? '0');
    final until = int.parse(await _storage.read(key: 'pin_locked_until') ?? '0');
    final wait = ((until - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    if (wait > 0) return wait;

    final salt = await _storage.read(key: 'pin_salt') ?? '';
    if (_hash(pin, salt) == await _storage.read(key: 'pin_hash')) {
      await _storage.delete(key: 'pin_fails');
      return null;
    }
    // 5 free attempts, then 30s, 60s, 120s… cooldown.
    await _storage.write(key: 'pin_fails', value: '${fails + 1}');
    if (fails + 1 >= 5) {
      final secs = 30 * pow(2, fails + 1 - 5).toInt();
      await _storage.write(
          key: 'pin_locked_until', value: '${DateTime.now().millisecondsSinceEpoch + secs * 1000}');
      return secs;
    }
    return 0;
  }

  static Future<bool> biometricEnabled() async => await _storage.read(key: 'biometric') != 'off';
  static Future<void> setBiometric(bool on) => _storage.write(key: 'biometric', value: on ? 'on' : 'off');
}

/// true = app content hidden behind the lock screen.
class LockController extends Notifier<bool> {
  DateTime? _backgroundedAt;
  @override
  bool build() => true; // cold start is always locked

  void unlock() => state = false;
  void lock() => state = true;
  void backgrounded() => _backgroundedAt ??= DateTime.now();
  void resumed() {
    final at = _backgroundedAt;
    _backgroundedAt = null;
    if (at != null && DateTime.now().difference(at) > lockTimeout) state = true;
  }
}

final lockProvider = NotifierProvider<LockController, bool>(LockController.new);

/// App-switcher privacy shield: true while inactive/paused.
class ObscureController extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final obscureProvider = NotifierProvider<ObscureController, bool>(ObscureController.new);

class PrivacyShield extends StatelessWidget {
  const PrivacyShield({super.key});
  @override
  Widget build(BuildContext context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          color: kBg.withValues(alpha: 0.7),
          alignment: Alignment.center,
          child: const AppLogo(size: 84),
        ),
      );
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: const LinearGradient(colors: [Color(0xFF2F6BFF), Color(0xFF8A5CFF)]),
        ),
        child: Icon(Icons.autorenew_rounded, size: size * 0.55, color: Colors.white),
      );
}

/// Full-screen Face ID + 6-digit glass PIN gate. [setup] = create a PIN first.
class LiquidGlassLockScreen extends ConsumerStatefulWidget {
  const LiquidGlassLockScreen({super.key, this.setup = false, this.onDone});
  final bool setup;
  final VoidCallback? onDone;
  @override
  ConsumerState<LiquidGlassLockScreen> createState() => _LockState();
}

class _LockState extends ConsumerState<LiquidGlassLockScreen> {
  final _auth = LocalAuthentication();
  String _pin = '';
  String? _firstPin; // setup: first entry awaiting confirmation
  String? _message;
  int _shake = 0;
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    if (!widget.setup) _initBiometrics();
  }

  Future<void> _initBiometrics() async {
    final enabled = await PinStore.biometricEnabled();
    final can = await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    if (!mounted) return;
    setState(() => _bioAvailable = enabled && can);
    if (_bioAvailable) _biometric();
  }

  Future<void> _biometric() async {
    try {
      final ok = await _auth.authenticate(localizedReason: 'Unlock your subscriptions', biometricOnly: true);
      if (ok) _unlocked();
    } catch (_) {
      // Dismissed / unavailable / locked-out → PIN pad stays.
    }
  }

  void _unlocked() {
    HapticFeedback.mediumImpact();
    ref.read(lockProvider.notifier).unlock();
    widget.onDone?.call();
  }

  void _fail(String msg) {
    HapticFeedback.heavyImpact();
    setState(() {
      _pin = '';
      _message = msg;
      _shake++;
    });
  }

  Future<void> _tap(String d) async {
    if (_pin.length >= _pinLength) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += d;
      _message = null;
    });
    if (_pin.length < _pinLength) return;

    if (widget.setup) {
      if (_firstPin == null) {
        setState(() {
          _firstPin = _pin;
          _pin = '';
        });
      } else if (_firstPin == _pin) {
        await PinStore.setPin(_pin);
        _unlocked();
      } else {
        _firstPin = null;
        _fail("PINs didn't match — try again");
      }
      return;
    }

    final wait = await PinStore.verify(_pin);
    if (wait == null) return _unlocked();
    _fail(wait > 0 ? 'Too many attempts. Try again in ${wait}s' : 'Incorrect PIN');
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.setup ? (_firstPin == null ? 'Create a 6-digit PIN' : 'Confirm your PIN') : 'Enter PIN';
    return Material(
      color: Colors.transparent,
      child: Ambient(
        child: SafeArea(
          child: Column(children: [
            const Spacer(),
            const AppLogo(),
            const SizedBox(height: 24),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pinLength, (i) {
                final filled = i < _pin.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: springBounce,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: filled ? 16 : 14,
                  height: filled ? 16 : 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? Colors.white : Colors.transparent,
                    border: Border.all(color: Colors.white54, width: 1.5),
                  ),
                );
              }),
            )
                .animate(key: ValueKey(_shake), autoPlay: _shake > 0)
                .shakeX(hz: 6, amount: 10, duration: 400.ms),
            SizedBox(
              height: 32,
              child: Center(
                  child: Text(_message ?? '', style: const TextStyle(color: kCrimson, fontSize: 13))),
            ),
            const Spacer(),
            _keypad(),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  Widget _keypad() {
    Widget key(Widget child, VoidCallback? onTap, {String? label}) => Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: 76,
              height: 76,
              child: onTap == null
                  ? null
                  : DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: kSurfaceHi, border: Border.all(color: kLine)),
                      child: Center(child: child),
                    ),
            ),
          ),
        );
    Widget digit(String d) => key(Text(d, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w400)),
        () => _tap(d), label: d);

    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: r.map(digit).toList()),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          key(const Icon(Icons.face_unlock_outlined, size: 30), _bioAvailable ? _biometric : null, label: 'Face ID'),
          digit('0'),
          key(const Icon(Icons.backspace_outlined), _backspace, label: 'Delete'),
        ]),
      ),
    ]);
  }
}
