import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, AuthException, AuthState;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'brand_mark.dart';
import 'data.dart';
import 'mail_apps.dart';
import 'stage.dart';
import 'ui.dart';

// ───────── Sign in ─────────
// The last beat of the onboarding story: after the forgotten trial took the last penny,
// the W arrives on the same violet stage and promises it won't happen again. A white
// Google pill, a quiet email pill, and the legal links underneath. Email moves to its
// own screen: the address, then "Check your inbox" with a button straight into Gmail
// (or whichever app the address points to). The link in the email verifies and deep
// links back to wince://login-callback, where supabase_flutter finishes signing in.

const kPrivacyUrl = 'https://mustaphi-dev.github.io/subscription-tracker/privacy.html';
const kTermsUrl = 'https://mustaphi-dev.github.io/subscription-tracker/terms.html';
const _heroStill = 'assets/onboarding/signin.jpg';
const _heroVideo = 'assets/onboarding/signin.mp4';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInState();
}

class _SignInState extends State<SignInScreen> {
  VideoPlayerController? _video;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _video ??= stageVideo(_heroVideo, play: !MediaQuery.disableAnimationsOf(context));
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  void _google() {
    // UI only for now; Google sign-in gets wired up with Supabase OAuth later.
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: kSurfaceHi,
          content: Text('Google sign-in is coming soon. Use email for now.', style: TextStyle(color: kText)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBg,
    body: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1400),
      builder: (context, t, _) => Stack(
        fit: StackFit.expand,
        children: [
          const StagePlate(),
          Opacity(
            opacity: _span(t, 0, 0.5),
            child: Transform.scale(scale: 1.03 - 0.03 * _span(t, 0, 1), child: StageScene(still: _heroStill, video: _video)),
          ),
          const _Scrim(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  _rise(_span(t, 0.15, 0.6), const Masthead()),
                  const Spacer(),
                  _rise(_span(t, 0.3, 0.8), const _Headline('Never wince\nagain.'), dy: 22),
                  const SizedBox(height: 14),
                  _rise(
                    _span(t, 0.4, 0.9),
                    const _Body('Every subscription and free trial, watched.\nWe warn you before one takes a penny.'),
                  ),
                  const SizedBox(height: 30),
                  _rise(
                    _span(t, 0.5, 1),
                    Column(
                      children: [
                        Pill(onTap: _google, icon: const FaIcon(FontAwesomeIcons.google, size: 18), label: 'Continue with Google'),
                        const SizedBox(height: 12),
                        Pill.quiet(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            context.push('/signin/email');
                          },
                          icon: const FaIcon(FontAwesomeIcons.envelope, size: 18),
                          label: 'Continue with email',
                        ),
                      ],
                    ),
                    dy: 20,
                  ),
                  const SizedBox(height: 26),
                  Opacity(opacity: _span(t, 0.6, 1), child: const LegalLinks()),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ───────── Email ─────────

enum _Step { ask, sent, signedIn }

/// Full-screen email sign-in: the address, then "Check your inbox" with a button that
/// opens the user's mail app. Tapping the link in the email verifies it and deep links
/// back here; the screen says "You're in" and moves on.
class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key});
  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  static const _cooldown = 60;
  static final _shape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  final _email = TextEditingController();
  final _focus = FocusNode();
  late final StreamSubscription<AuthState> _auth;
  VideoPlayerController? _video;
  Timer? _tick;
  _Step _step = _Step.ask;
  bool _busy = false;
  String? _error;
  int _wait = 0; // seconds until another link can be sent

  String get _address => _email.text.trim();
  bool get _valid => _shape.hasMatch(_address);
  MailApp get _app => MailApp.forEmail(_address);

  @override
  void initState() {
    super.initState();
    _email.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
    // The link comes back through supabase_flutter: a session on success, a stream error
    // (expired or already used) on failure.
    _auth = db.auth.onAuthStateChange.listen(
      (s) {
        if (s.event == AuthChangeEvent.signedIn && s.session != null) _signedIn();
      },
      onError: (Object e) {
        if (!mounted || _step != _Step.sent) return;
        setState(() {
          _error = e is AuthException && (e.statusCode == 'otp_expired' || e.code == 'access_denied')
              ? 'That link has expired or was already used. Send a new one.'
              : 'That link didn\'t work. Send a new one.';
          _wait = 0;
        });
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _video ??= stageVideo(_heroVideo, play: !MediaQuery.disableAnimationsOf(context));
  }

  @override
  void dispose() {
    _auth.cancel();
    _tick?.cancel();
    _video?.dispose();
    _email.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_valid || _busy || _wait > 0) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await db.auth.signInWithOtp(email: _address, emailRedirectTo: 'wince://login-callback');
      if (!mounted) return;
      _focus.unfocus();
      setState(() => _step = _Step.sent);
      _startCooldown();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _error = 'Something went wrong. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCooldown() {
    _tick?.cancel();
    setState(() => _wait = _cooldown);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait = math.max(0, _wait - 1));
      if (_wait == 0) t.cancel();
    });
  }

  Future<void> _openMail() async {
    HapticFeedback.selectionClick();
    final opened = await openMailApp(_app);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: kSurfaceHi,
            content: Text('Open your email app and tap the link from Wince.', style: TextStyle(color: kText)),
          ),
        );
    }
  }

  void _signedIn() {
    if (!mounted || _step == _Step.signedIn) return;
    HapticFeedback.heavyImpact();
    setState(() => _step = _Step.signedIn);
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) context.go('/');
    });
  }

  void _back() {
    if (_step == _Step.sent) {
      setState(() {
        _step = _Step.ask;
        _error = null;
      });
      _focus.requestFocus();
    } else if (_step == _Step.ask) {
      context.canPop() ? context.pop() : context.go('/signin');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _step == _Step.ask,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      backgroundColor: kBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const StagePlate(),
          // The W comes back once the link is on its way.
          AnimatedOpacity(
            opacity: _step == _Step.ask ? 0 : 1,
            duration: const Duration(milliseconds: 500),
            child: StageScene(still: _heroStill, video: _video),
          ),
          const _Scrim(),
          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Masthead(),
                      if (_step != _Step.signedIn)
                        Positioned(
                          left: 4,
                          child: IconButton(
                            onPressed: _back,
                            tooltip: 'Back',
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: kText),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a), child: child),
                    ),
                    child: switch (_step) {
                      _Step.ask => _askView(),
                      _Step.sent => _sentView(),
                      _Step.signedIn => _signedInView(),
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _askView() => Padding(
    key: const ValueKey('ask'),
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      children: [
        const Spacer(flex: 3),
        const _Headline("What's your email?"),
        const SizedBox(height: 12),
        const _Body("We'll send you a link. Tap it and you're in,\nno password to remember."),
        const SizedBox(height: 28),
        _EmailField(controller: _email, focus: _focus, error: _error != null, onSubmit: _send),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kCrimson, fontSize: 13.5)),
                ),
        ),
        const SizedBox(height: 16),
        Pill(
          onTap: _valid && !_busy ? _send : null,
          icon: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.arrow_forward_rounded, size: 20),
          label: _busy ? 'Sending link' : 'Send link',
        ),
        const SizedBox(height: 16),
        const _Agreement(),
        const Spacer(flex: 2),
      ],
    ),
  );

  Widget _sentView() => Padding(
    key: const ValueKey('sent'),
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      children: [
        const Spacer(),
        const _Headline('Check your inbox'),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'We sent a sign-in link to\n'),
              TextSpan(text: _address, style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
              const TextSpan(text: '.\nTap it and you\'ll come straight back here.'),
            ],
          ),
          textAlign: TextAlign.center,
          style: _Body.style,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kCrimson, fontSize: 13.5)),
                ),
        ),
        const SizedBox(height: 28),
        Pill(onTap: _openMail, icon: const FaIcon(FontAwesomeIcons.envelope, size: 18), label: _app.action),
        const SizedBox(height: 12),
        Pill.quiet(
          onTap: _wait > 0 || _busy ? null : _send,
          icon: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kText))
              : const Icon(Icons.refresh_rounded, size: 20),
          label: _wait > 0 ? 'Resend in 0:${_wait.toString().padLeft(2, '0')}' : 'Resend link',
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _back,
          child: Text('Use a different email', style: TextStyle(color: kText.withValues(alpha: 0.72), fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 2),
        Text("Can't see it? Check spam and promotions.", style: TextStyle(color: kText.withValues(alpha: 0.42), fontSize: 13)),
        const SizedBox(height: 14),
      ],
    ),
  );

  Widget _signedInView() => const Padding(
    key: ValueKey('in'),
    padding: EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      children: [
        Spacer(),
        _Headline("You're in."),
        SizedBox(height: 12),
        _Body('Verified. Taking you to Wince.'),
        SizedBox(height: 120),
      ],
    ),
  );
}

// ───────── Pieces ─────────

/// The flat W and the name, small, at the top of the screen like a masthead.
class Masthead extends StatelessWidget {
  const Masthead({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const BrandMark(size: 30),
      const SizedBox(width: 6),
      Text('Wince', style: display(22, weight: FontWeight.w600).copyWith(letterSpacing: -0.6)),
    ],
  );
}

class _Headline extends StatelessWidget {
  const _Headline(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: TextAlign.center, style: display(38, weight: FontWeight.w600).copyWith(height: 1.06, letterSpacing: -1.5));
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;
  static final style = TextStyle(color: kText.withValues(alpha: 0.6), fontSize: 15, height: 1.45, letterSpacing: -0.1);
  @override
  Widget build(BuildContext context) => Text(text, textAlign: TextAlign.center, style: style);
}

/// Darkens the bottom of the stage so the type and buttons always read.
class _Scrim extends StatelessWidget {
  const _Scrim();
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kBg.withValues(alpha: 0), kBg.withValues(alpha: 0), kBg.withValues(alpha: 0.75), kBg],
          stops: const [0, 0.45, 0.68, 1],
        ),
      ),
    ),
  );
}

class _EmailField extends StatelessWidget {
  const _EmailField({required this.controller, required this.focus, required this.error, required this.onSubmit});
  final TextEditingController controller;
  final FocusNode focus;
  final bool error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: focus.hasFocus ? 0.1 : 0.07),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(
        color: error ? kCrimson.withValues(alpha: 0.7) : Colors.white.withValues(alpha: focus.hasFocus ? 0.28 : 0.12),
      ),
    ),
    alignment: Alignment.center,
    child: TextField(
      controller: controller,
      focusNode: focus,
      autofocus: true,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.send,
      autofillHints: const [AutofillHints.email],
      autocorrect: false,
      enableSuggestions: false,
      textAlign: TextAlign.center,
      onSubmitted: (_) => onSubmit(),
      cursorColor: kText,
      style: const TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        filled: false,
        isCollapsed: true,
        border: InputBorder.none,
        hintText: 'you@example.com',
        hintStyle: TextStyle(color: kText.withValues(alpha: 0.32), fontSize: 17, fontWeight: FontWeight.w500),
      ),
    ),
  );
}

/// "By continuing, you agree to the Terms and Privacy Policy", with both as links.
class _Agreement extends StatefulWidget {
  const _Agreement();
  @override
  State<_Agreement> createState() => _AgreementState();
}

class _AgreementState extends State<_Agreement> {
  late final _terms = TapGestureRecognizer()..onTap = () => _openLegal(kTermsUrl);
  late final _privacy = TapGestureRecognizer()..onTap = () => _openLegal(kPrivacyUrl);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = TextStyle(color: kText.withValues(alpha: 0.78), fontWeight: FontWeight.w500);
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'By continuing, you agree to the '),
          TextSpan(text: 'Terms', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(color: kText.withValues(alpha: 0.45), fontSize: 12.5, height: 1.4),
    );
  }
}

void _openLegal(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);

/// Privacy Policy · Terms of Service, opening the GitHub Pages copies.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  Widget _link(String text, String url) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => _openLegal(url),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(text, style: TextStyle(color: kText.withValues(alpha: 0.72), fontSize: 14, fontWeight: FontWeight.w500)),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _link('Privacy Policy', kPrivacyUrl),
      Container(width: 3, height: 3, margin: const EdgeInsets.symmetric(horizontal: 6), decoration: const BoxDecoration(color: kFaint, shape: BoxShape.circle)),
      _link('Terms of Service', kTermsUrl),
    ],
  );
}

/// Full-width stadium button with an icon before the label; presses down slightly.
/// White by default; [Pill.quiet] is the translucent secondary.
class Pill extends StatefulWidget {
  const Pill({super.key, required this.onTap, required this.icon, required this.label})
    : background = Colors.white,
      foreground = Colors.black,
      border = null;
  Pill.quiet({super.key, required this.onTap, required this.icon, required this.label})
    : background = Colors.white.withValues(alpha: 0.08),
      foreground = kText,
      border = Colors.white.withValues(alpha: 0.1);
  final VoidCallback? onTap;
  final Color background, foreground;
  final Color? border;
  final Widget icon;
  final String label;
  @override
  State<Pill> createState() => _PillState();
}

class _PillState extends State<Pill> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.45,
            duration: const Duration(milliseconds: 150),
            child: Container(
              height: 56,
              decoration: ShapeDecoration(
                color: widget.background,
                shape: StadiumBorder(side: widget.border == null ? BorderSide.none : BorderSide(color: widget.border!)),
              ),
              child: IconTheme(
                data: IconThemeData(color: widget.foreground),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    widget.icon,
                    const SizedBox(width: 10),
                    Text(widget.label, style: TextStyle(color: widget.foreground, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _span(double t, double a, double b, [Curve curve = Curves.easeOutCubic]) => curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

Widget _rise(double r, Widget child, {double dy = 16}) => Opacity(
  opacity: r.clamp(0.0, 1.0),
  child: Transform.translate(offset: Offset(0, (1 - r) * dy), child: child),
);
