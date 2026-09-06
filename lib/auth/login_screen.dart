import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/auth/turnstile_dialog.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';
import 'package:url_launcher/url_launcher.dart';

enum _LoginMode { providers, enterEmail, enterOtp }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _LoginMode _mode = .providers;
  bool _appleLoading = false;
  bool _googleLoading = false;
  bool _guestLoading = false;
  bool _emailLoading = false;
  bool _otpLoading = false;

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  int _resendCooldown = 0;
  Timer? _resendTimer;

  bool get _anyLoading =>
      _appleLoading || _googleLoading || _guestLoading || _emailLoading || _otpLoading;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendCooldown = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _run(
    Future<void> Function() action,
    void Function(bool) setLoading, {
    required String during,
    VoidCallback? onSuccess,
  }) async {
    setLoading(true);
    try {
      await action();
      onSuccess?.call();
      // Navigation happens via the router's auth redirect.
    } catch (e, s) {
      reportNonFatal(e, s, during: during);
      if (mounted) {
        final message = e is AuthException
            ? e.message
            : "Couldn't sign you in - give it another try.";
        showPTSnack(context, message, kind: .error);
      }
    } finally {
      if (mounted) setLoading(false);
    }
  }

  void _signInWithApple() => _run(
    AuthService.instance.signInWithApple,
    (v) => setState(() => _appleLoading = v),
    during: 'signing in with Apple',
  );

  void _signInWithGoogle() => _run(
    AuthService.instance.signInWithGoogle,
    (v) => setState(() => _googleLoading = v),
    during: 'signing in with Google',
  );

  Future<void> _sendEmailOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      showPTSnack(context, 'Please enter a valid email address.', kind: .info);
      return;
    }
    String? captchaToken;
    final captchaRequired = (Env.turnstileSiteKey ?? '').isNotEmpty;
    if (captchaRequired) {
      captchaToken = await showTurnstileDialog(context);
      if (captchaToken == null) return;
    }
    await _run(
      () => AuthService.instance.sendEmailOtp(email, captchaToken: captchaToken),
      (v) => setState(() => _emailLoading = v),
      during: 'sending email verification code',
      onSuccess: () {
        setState(() {
          _mode = .enterOtp;
          _otpController.clear();
          _startResendTimer();
        });
        showPTSnack(context, 'Verification code sent to $email', kind: .success);
      },
    );
  }

  Future<void> _verifyEmailOtp() async {
    final email = _emailController.text.trim();
    final token = _otpController.text.trim();
    if (token.length != 6) {
      showPTSnack(context, 'Please enter the 6-digit code.', kind: .info);
      return;
    }
    await _run(
      () => AuthService.instance.verifyEmailOtp(email: email, token: token),
      (v) => setState(() => _otpLoading = v),
      during: 'verifying email OTP',
    );
  }

  Future<void> _continueAsGuest() async {
    String? captchaToken;
    final captchaRequired = (Env.turnstileSiteKey ?? '').isNotEmpty;
    trace('guest sign-in started', category: 'auth', data: {'captcha': captchaRequired});
    if (captchaRequired) {
      captchaToken = await showTurnstileDialog(context);
      if (captchaToken == null) {
        trace('guest sign-in abandoned: no captcha token', category: 'auth');
        return;
      }
      trace('captcha token acquired', category: 'auth');
    }
    await _run(
      () => AuthService.instance.signInAsGuest(captchaToken: captchaToken),
      (v) => setState(() => _guestLoading = v),
      during: 'signing in as a guest',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: PTResponsive(
          desktop: (_) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: GlassPanel(
                radius: 28,
                opacity: 0.5,
                blur: 32,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 44),
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    const _Brand(),
                    const SizedBox(height: 34),
                    _actions(),
                    const SizedBox(height: 26),
                    const PTEntrance(delay: Duration(milliseconds: 240), child: _TermsNote()),
                  ],
                ),
              ),
            ),
          ),
          landscape: (_) => SafeArea(
            child: Row(
              children: [
                const Expanded(child: Center(child: _Brand())),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: .min,
                        children: [
                          _actions(),
                          const SizedBox(height: 14),
                          const PTEntrance(delay: Duration(milliseconds: 240), child: _TermsNote()),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          portrait: (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(),
                  const _Brand(large: true),
                  const Spacer(),
                  _actions(buttonHeight: 54),
                  const SizedBox(height: 16),
                  const PTEntrance(delay: Duration(milliseconds: 240), child: _TermsNote()),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions({double buttonHeight = 52}) {
    return PTEntrance(
      delay: const Duration(milliseconds: 180),
      child: AnimatedSwitcher(
        duration: PTMotion.functional(context, PTMotion.state),
        switchInCurve: PTMotion.enter,
        switchOutCurve: PTMotion.exit,
        child: switch (_mode) {
          .providers => _providersView(buttonHeight: buttonHeight),
          .enterEmail => _enterEmailView(buttonHeight: buttonHeight),
          .enterOtp => _enterOtpView(buttonHeight: buttonHeight),
        },
      ),
    );
  }

  Widget _providersView({required double buttonHeight}) {
    final hasApple = AuthService.instance.isAppleSupported;
    return Column(
      key: const ValueKey('providers'),
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 11,
      children: [
        if (hasApple)
          AppleButton(
            label: 'Continue with Apple',
            loading: _appleLoading,
            onPressed: _anyLoading ? null : _signInWithApple,
          ),
        GoogleButton(
          label: 'Continue with Google',
          loading: _googleLoading,
          onPressed: _anyLoading ? null : _signInWithGoogle,
        ),
        PTButton(
          label: 'Continue with email',
          icon: Symbols.mail_rounded,
          variant: .secondary,
          height: buttonHeight,
          onPressed: _anyLoading ? null : () => setState(() => _mode = .enterEmail),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            spacing: 14,
            children: [
              Expanded(child: Container(height: 1, color: PTColors.white(0.12))),
              Text('or', style: PTText.finePrint),
              Expanded(child: Container(height: 1, color: PTColors.white(0.12))),
            ],
          ),
        ),
        PTButton(
          label: 'Continue as guest',
          icon: Symbols.person_rounded,
          variant: .secondary,
          height: buttonHeight,
          loading: _guestLoading,
          onPressed: _anyLoading ? null : _continueAsGuest,
        ),
      ],
    );
  }

  Widget _enterEmailView({required double buttonHeight}) {
    return Column(
      key: const ValueKey('enterEmail'),
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Symbols.arrow_back_rounded, color: Colors.white70),
              onPressed: _anyLoading ? null : () => setState(() => _mode = .providers),
              tooltip: 'Back',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Sign in with email', style: PTText.cardHeading.copyWith(fontSize: 17)),
            ),
          ],
        ),
        Text(
          "We'll send a 6-digit verification code to your inbox.",
          style: PTText.body.copyWith(color: PTColors.white(0.65), fontSize: 13.5),
        ),
        TextField(
          controller: _emailController,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendEmailOtp(),
          style: PTText.body.copyWith(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'name@example.com',
            hintStyle: PTText.body.copyWith(color: PTColors.white(0.35)),
            prefixIcon: Icon(Symbols.mail_rounded, size: 20, color: PTColors.white(0.5)),
            filled: true,
            fillColor: PTColors.glass(0.35),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: PTColors.white(0.15)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: PTColors.white(0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: PTColors.primary, width: 1.5),
            ),
          ),
        ),
        PTButton(
          label: 'Send verification code',
          icon: Symbols.send_rounded,
          variant: .primary,
          height: buttonHeight,
          loading: _emailLoading,
          onPressed: _anyLoading ? null : _sendEmailOtp,
        ),
      ],
    );
  }

  Widget _enterOtpView({required double buttonHeight}) {
    return Column(
      key: const ValueKey('enterOtp'),
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Symbols.arrow_back_rounded, color: Colors.white70),
              onPressed: _anyLoading ? null : () => setState(() => _mode = .enterEmail),
              tooltip: 'Change email',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Check your inbox', style: PTText.cardHeading.copyWith(fontSize: 17)),
            ),
          ],
        ),
        Text.rich(
          TextSpan(
            text: 'We sent a 6-digit code to ',
            style: PTText.body.copyWith(color: PTColors.white(0.65), fontSize: 13.5),
            children: [
              TextSpan(
                text: _emailController.text.trim(),
                style: const TextStyle(fontWeight: .w600, color: Colors.white),
              ),
              const TextSpan(text: '. Enter it below to sign in.'),
            ],
          ),
        ),
        TextField(
          controller: _otpController,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: .center,
          textInputAction: TextInputAction.done,
          style: PTText.body.copyWith(
            fontSize: 22,
            letterSpacing: 6,
            fontWeight: .w700,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: PTText.body.copyWith(
              fontSize: 22,
              letterSpacing: 6,
              color: PTColors.white(0.2),
            ),
            filled: true,
            fillColor: PTColors.glass(0.35),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: PTColors.white(0.15)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: PTColors.white(0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: PTColors.primary, width: 1.5),
            ),
          ),
          onChanged: (code) {
            if (code.trim().length == 6) {
              _verifyEmailOtp();
            }
          },
        ),
        PTButton(
          label: 'Verify code',
          icon: Symbols.check_rounded,
          variant: .primary,
          height: buttonHeight,
          loading: _otpLoading,
          onPressed: _anyLoading ? null : _verifyEmailOtp,
        ),
        Center(
          child: TextButton(
            onPressed: _resendCooldown > 0 || _anyLoading ? null : _sendEmailOtp,
            child: Text(
              _resendCooldown > 0 ? 'Resend code in ${_resendCooldown}s' : 'Resend code',
              style: PTText.finePrint.copyWith(
                color: _resendCooldown > 0 ? PTColors.white(0.4) : const Color(0xFFB79CFF),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Brand extends StatefulWidget {
  const _Brand({this.large = false});

  final bool large;

  @override
  State<_Brand> createState() => _BrandState();
}

class _BrandState extends State<_Brand> with SingleTickerProviderStateMixin {
  // The one breathing element on this screen - the lobby's is its greeting.
  // Isolated behind a RepaintBoundary so a looping shadow can't dirty the rest
  // of the card every frame.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      _breath.stop();
      _breath.value = 0;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoSize = widget.large ? 84.0 : 72.0;
    return Column(
      mainAxisSize: .min,
      children: [
        PTEntrance(
          scaleFrom: 0.9,
          offset: 0,
          duration: const Duration(milliseconds: 400),
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _breath,
              builder: (context, child) => Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  gradient: PTColors.brandGradient,
                  borderRadius: BorderRadius.circular(logoSize * 0.3),
                  boxShadow: [
                    BoxShadow(
                      color: PTColors.primary.withValues(alpha: 0.45 + 0.1 * _breath.value),
                      blurRadius: 32 + 8 * _breath.value,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: child,
              ),
              child: Icon(Icons.play_arrow_rounded, size: logoSize * 0.53, color: Colors.white),
            ),
          ),
        ),
        SizedBox(height: widget.large ? 26 : 22),
        PTEntrance(
          delay: const Duration(milliseconds: 60),
          child: Text(
            'SyncTogether',
            style: PTText.display.copyWith(fontSize: widget.large ? 32 : 30),
          ),
        ),
        const SizedBox(height: 8),
        PTEntrance(
          delay: const Duration(milliseconds: 120),
          child: Text(
            'Movie nights with your people,\nperfectly in sync.',
            textAlign: .center,
            style: PTText.body.copyWith(color: PTColors.white(0.6)),
          ),
        ),
      ],
    );
  }
}

class _TermsNote extends StatelessWidget {
  const _TermsNote();

  @override
  Widget build(BuildContext context) {
    final linkStyle = PTText.finePrint.copyWith(color: const Color(0xFFB79CFF));
    return Text.rich(
      TextSpan(
        text: 'By continuing you agree to our ',
        style: PTText.finePrint,
        children: [
          TextSpan(
            text: 'Terms',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(
                Uri.parse('https://synctogether.app/terms'),
                mode: LaunchMode.externalApplication,
              ),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy policy',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(
                Uri.parse('https://synctogether.app/privacy'),
                mode: LaunchMode.externalApplication,
              ),
          ),
        ],
      ),
      textAlign: .center,
    );
  }
}
