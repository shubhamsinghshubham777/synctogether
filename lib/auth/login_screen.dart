import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/app_version.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/auth/turnstile_dialog.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/logo.dart';
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
  bool _passwordLoading = false;
  bool _obscurePassword = true;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  int _resendCooldown = 0;
  Timer? _resendTimer;

  bool get _anyLoading =>
      _appleLoading ||
      _googleLoading ||
      _guestLoading ||
      _emailLoading ||
      _otpLoading ||
      _passwordLoading;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
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
            : "Couldn't sign you in. Give it another try.";
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
    final email = _emailController.text.trim().toLowerCase();
    if (!_looksLikeEmail(email)) {
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

  /// Signs in with the password the account holder set, if they set one.
  ///
  /// The one-time code stays available beside it, which is what makes this
  /// safe to offer: an account with no password, or a forgotten one, is never
  /// a lockout, so there is no reset-link flow to build or to get wrong.
  Future<void> _signInWithPassword() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    if (!_looksLikeEmail(email)) {
      showPTSnack(context, 'Please enter a valid email address.', kind: .info);
      return;
    }
    if (password.isEmpty) {
      showPTSnack(context, 'Enter your password, or ask for a code instead.', kind: .info);
      return;
    }

    String? captchaToken;
    if ((Env.turnstileSiteKey ?? '').isNotEmpty) {
      captchaToken = await showTurnstileDialog(context);
      if (captchaToken == null) return;
    }
    if (!mounted) return;

    setState(() => _passwordLoading = true);
    try {
      await AuthService.instance.signInWithPassword(
        email: email,
        password: password,
        captchaToken: captchaToken,
      );
      // Navigation happens via the router's auth redirect.
    } on AuthException catch (e) {
      // Wrong password is a normal answer, not a fault worth reporting - and
      // the advice that matters is that the code still works.
      final wrongCredentials = e.message.toLowerCase().contains('invalid login credentials');
      if (!wrongCredentials) {
        reportNonFatal(e, StackTrace.current, during: 'signing in with a password');
      }
      if (mounted) {
        showPTSnack(
          context,
          wrongCredentials
              ? "That password doesn't match. Try again, or email yourself a code instead."
              : e.message,
          kind: .error,
        );
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'signing in with a password');
      if (mounted) {
        showPTSnack(context, "Couldn't sign you in. Give it another try.", kind: .error);
      }
    } finally {
      if (mounted) setState(() => _passwordLoading = false);
    }
  }

  static bool _looksLikeEmail(String email) =>
      email.isNotEmpty && email.contains('@') && email.contains('.');

  Future<void> _verifyEmailOtp() async {
    final email = _emailController.text.trim().toLowerCase();
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
          // Tablets fall back here too, hence the SafeArea.
          desktop: (context) => SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final short = box.maxHeight < 720;
                // Two columns while the marquee has room to be a marquee;
                // below that one centred column (portrait tablets, narrow
                // desktop windows).
                if (box.maxWidth < 900) return _stacked(short: short);
                final officeWidth = box.maxWidth >= 1280 ? 520.0 : 440.0;
                final marqueeWidth = box.maxWidth - officeWidth;
                final wide = marqueeWidth >= 760;
                final gutter = wide ? 72.0 : 52.0;
                // "Take your" sets at roughly 4.4 em, so the headline is sized
                // from the column it has to fit, up to the board's 132.
                final headline = ((marqueeWidth - gutter - 48) / 4.6)
                    .clamp(56.0, short ? 84.0 : 132.0)
                    .toDouble();
                return Row(
                  crossAxisAlignment: .stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(gutter, short ? 32 : 56, 48, short ? 32 : 64),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: box.maxHeight - (short ? 64 : 120),
                          ),
                          child: Column(
                            crossAxisAlignment: .start,
                            mainAxisAlignment: .spaceBetween,
                            children: [
                              const _WordmarkRow(),
                              SizedBox(height: short ? 28 : 48),
                              _Marquee(headlineSize: headline),
                              SizedBox(height: short ? 28 : 48),
                              if (!short)
                                Row(
                                  crossAxisAlignment: .center,
                                  children: [
                                    const Flexible(child: SizedBox(width: 520, child: _AdmitOne())),
                                    if (marqueeWidth >= 880) ...[
                                      const SizedBox(width: 32),
                                      const SizedBox(width: 220, child: _FirstNightChecks()),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // The box office: a Seat column down the right edge, not
                    // a floating card.
                    Container(
                      width: officeWidth,
                      decoration: const BoxDecoration(
                        color: PTColors.glassBase,
                        border: Border(left: BorderSide(color: PTColors.aisle)),
                      ),
                      child: Center(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: officeWidth >= 520 ? 64 : 48,
                            vertical: 32,
                          ),
                          child: Column(
                            mainAxisSize: .min,
                            crossAxisAlignment: .stretch,
                            children: [
                              _boxOfficeLabel(),
                              const SizedBox(height: 10),
                              _actions(heading: true),
                              const SizedBox(height: 32),
                              const PTEntrance(
                                delay: Duration(milliseconds: 240),
                                child: _TermsNote(align: .start),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          landscape: (_) => SafeArea(
            child: Row(
              children: [
                // Scale the marquee down rather than clip it on a 375-tall phone.
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(32, 16, 16, 16),
                    child: Align(
                      alignment: .centerLeft,
                      child: FittedBox(
                        fit: .scaleDown,
                        alignment: .centerLeft,
                        child: SizedBox(
                          width: 340,
                          child: _Marquee(headlineSize: 48, wordmark: true),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      child: Column(
                        mainAxisSize: .min,
                        children: [
                          _actions(compactGuest: true),
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
          portrait: (_) => _stacked(short: false, phone: true),
        ),
      ),
    );
  }

  /// One column: wordmark, marquee, the first-night ticket, then the sign-in
  /// stack. Scrolls once the content outgrows the screen (320x568, the OTP
  /// view with the keyboard up, 2.0x text); the spacer still pushes the
  /// buttons down whenever it fits, where a thumb reaches them.
  Widget _stacked({required bool short, bool phone = false}) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          // The ticket is decoration; a phone that cannot fit it and the
          // buttons without scrolling drops it rather than push sign-in below
          // the fold.
          final showTicket = box.maxHeight >= 700;
          final slack = (box.maxHeight - (showTicket ? 800 : 640)) / 2;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: phone ? 20 : 48),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: box.maxHeight,
                  maxWidth: phone ? double.infinity : 460,
                ),
                // No IntrinsicHeight: mid-switch the AnimatedSwitcher holds both
                // views, and intrinsics then undercount. The slack between the
                // marquee and the buttons is computed from the window instead.
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    SizedBox(height: phone ? 20 : 40),
                    const _WordmarkRow(spread: true, size: 20),
                    SizedBox(height: math.max(short ? 24.0 : 28.0, slack)),
                    _Marquee(headlineSize: phone ? 52 : 60, brief: true),
                    if (showTicket && _mode == .providers) ...[
                      const SizedBox(height: 28),
                      const _AdmitOne(),
                    ],
                    SizedBox(height: math.max(short ? 24.0 : 32.0, slack)),
                    _actions(buttonHeight: phone ? 50 : 52, compactGuest: true),
                    const SizedBox(height: 20),
                    const PTEntrance(delay: Duration(milliseconds: 240), child: _TermsNote()),
                    SizedBox(height: phone ? 24 : 40),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _boxOfficeLabel() => AnimatedSwitcher(
    duration: PTMotion.functional(context, PTMotion.state),
    layoutBuilder: (current, previous) =>
        Stack(alignment: .centerLeft, children: [...previous, ?current]),
    child: Text(
      switch (_mode) {
        .providers => 'BOX OFFICE',
        .enterEmail => 'BOX OFFICE · EMAIL',
        .enterOtp => 'BOX OFFICE · YOUR CODE',
      },
      key: ValueKey(_mode),
      style: PTText.label,
    ),
  );

  Widget _actions({double buttonHeight = 52, bool heading = false, bool compactGuest = false}) {
    return PTEntrance(
      delay: const Duration(milliseconds: 180),
      child: AnimatedSwitcher(
        duration: PTMotion.functional(context, PTMotion.state),
        switchInCurve: PTMotion.enter,
        switchOutCurve: PTMotion.exit,
        child: switch (_mode) {
          .providers => _providersView(
            buttonHeight: buttonHeight,
            heading: heading,
            compactGuest: compactGuest,
          ),
          .enterEmail => _enterEmailView(buttonHeight: buttonHeight),
          .enterOtp => _enterOtpView(buttonHeight: buttonHeight),
        },
      ),
    );
  }

  Widget _providersView({
    required double buttonHeight,
    required bool heading,
    required bool compactGuest,
  }) {
    final hasApple = AuthService.instance.isAppleSupported;
    return Column(
      key: const ValueKey('providers'),
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        if (heading) ...[
          Text('Show your ticket.', style: _officeHeading),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'One account keeps your name, streak and rooms on every device.',
              style: PTText.body.copyWith(fontSize: 14.5, height: 1.45, color: PTColors.white(0.7)),
            ),
          ),
        ],
        if (hasApple)
          _PaperSlab(
            child: AppleButton(
              label: 'Continue with Apple',
              loading: _appleLoading,
              onPressed: _anyLoading ? null : _signInWithApple,
            ),
          ),
        GoogleButton(
          outlined: true,
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
        if (compactGuest) ...[
          const SizedBox(height: 10),
          _guestLink(),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              spacing: 14,
              children: [
                const Expanded(
                  child: SizedBox(height: 1, child: ColoredBox(color: PTColors.rail)),
                ),
                Text('OR JUST WATCH', style: PTText.label.copyWith(fontSize: 10.5)),
                const Expanded(
                  child: SizedBox(height: 1, child: ColoredBox(color: PTColors.rail)),
                ),
              ],
            ),
          ),
          _guestCard(),
        ],
      ],
    );
  }

  static const _guestNote = 'Guest rooms seat 4 for an hour. Wiped after 3 days.';

  TextStyle get _guestLabel => PTText.body.copyWith(
    fontSize: 15,
    fontWeight: .w600,
    color: PTColors.fg,
    decoration: TextDecoration.underline,
    decorationColor: PTColors.white(0.6),
  );

  /// Guest entry on the box office: a dashed stub rather than a fourth
  /// button, because it is the one way in that keeps nothing.
  Widget _guestCard() {
    final enabled = !_anyLoading;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: PTPressable(
        enabled: enabled,
        pressedScale: 0.985,
        onTap: _continueAsGuest,
        child: CustomPaint(
          painter: const _DashedOutline(color: PTColors.rail, radius: PTRadius.panel),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              spacing: 14,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: .center,
                  decoration: BoxDecoration(
                    color: PTColors.aisle,
                    borderRadius: BorderRadius.circular(PTRadius.control),
                  ),
                  child: AnimatedSwitcher(
                    duration: PTMotion.functional(context, PTMotion.state),
                    child: _guestLoading
                        ? const PTLoader(key: ValueKey('loading'), size: 18)
                        : Icon(
                            Symbols.person_rounded,
                            key: const ValueKey('idle'),
                            size: 20,
                            color: PTColors.white(0.7),
                          ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 3,
                    children: [
                      Text('Continue as guest', style: _guestLabel),
                      Text(_guestNote, style: PTText.finePrint.copyWith(fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Phones: the guest way in as an underlined line with its note beneath.
  Widget _guestLink() {
    final enabled = !_anyLoading;
    return Column(
      mainAxisSize: .min,
      spacing: 10,
      children: [
        MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: PTPressable(
            enabled: enabled,
            onTap: _continueAsGuest,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: Row(
                mainAxisSize: .min,
                spacing: 10,
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: _guestLoading
                        ? const PTLoader(size: 16)
                        : Icon(Symbols.person_rounded, size: 20, color: PTColors.white(0.75)),
                  ),
                  Flexible(child: Text('Continue as guest', style: _guestLabel)),
                ],
              ),
            ),
          ),
        ),
        Text(_guestNote, textAlign: .center, style: PTText.finePrint.copyWith(fontSize: 12.5)),
      ],
    );
  }

  TextStyle get _officeHeading => PTText.display.copyWith(fontSize: 34, height: 1.05);

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
              icon: Icon(Symbols.arrow_back_rounded, color: PTColors.white(0.7)),
              onPressed: _anyLoading ? null : () => setState(() => _mode = .providers),
              tooltip: 'Back',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Sign in with email', style: _officeHeading.copyWith(fontSize: 26)),
            ),
          ],
        ),
        Text(
          'Enter your password, or have us email you a 6-digit code instead.',
          style: PTText.body.copyWith(color: PTColors.white(0.65), fontSize: 13.5),
        ),
        _RevealOnFocus(
          child: TextField(
            controller: _emailController,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            style: PTText.body.copyWith(color: PTColors.fg),
            decoration: _fieldDecoration(hint: 'name@example.com', icon: Symbols.mail_rounded),
          ),
        ),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _signInWithPassword(),
          style: PTText.body.copyWith(color: PTColors.fg),
          decoration: _fieldDecoration(
            hint: 'Password',
            icon: Symbols.lock_rounded,
            suffix: IconButton(
              icon: Icon(
                _obscurePassword ? Symbols.visibility_rounded : Symbols.visibility_off_rounded,
                size: 20,
                color: PTColors.white(0.5),
              ),
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        PTButton(
          label: 'Sign in',
          icon: Symbols.login_rounded,
          variant: .primary,
          height: buttonHeight,
          loading: _passwordLoading,
          onPressed: _anyLoading ? null : _signInWithPassword,
        ),
        // Always offered, never secondary in importance: an account only has a
        // password if its owner chose to set one, so the code is the path that
        // works for everybody.
        PTButton(
          label: 'Email me a 6-digit code',
          icon: Symbols.send_rounded,
          variant: .secondary,
          height: buttonHeight,
          loading: _emailLoading,
          onPressed: _anyLoading ? null : _sendEmailOtp,
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({required String hint, required IconData icon, Widget? suffix}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(PTRadius.panel),
      borderSide: BorderSide(color: PTColors.white(0.15)),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: PTText.body.copyWith(color: PTColors.white(0.35)),
      prefixIcon: Icon(icon, size: 20, color: PTColors.white(0.5)),
      suffixIcon: suffix,
      filled: true,
      fillColor: PTColors.glass(0.35),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PTRadius.panel),
        borderSide: const BorderSide(color: PTColors.primary, width: 1.5),
      ),
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
              icon: Icon(Symbols.arrow_back_rounded, color: PTColors.white(0.7)),
              onPressed: _anyLoading ? null : () => setState(() => _mode = .enterEmail),
              tooltip: 'Change email',
            ),
            const SizedBox(width: 4),
            Expanded(child: Text('Check your inbox', style: _officeHeading.copyWith(fontSize: 26))),
          ],
        ),
        Text.rich(
          TextSpan(
            text: 'We sent a 6-digit code to ',
            style: PTText.body.copyWith(color: PTColors.white(0.65), fontSize: 13.5),
            children: [
              TextSpan(
                text: _emailController.text.trim(),
                style: const TextStyle(fontWeight: .w600, color: PTColors.fg),
              ),
              const TextSpan(text: '. Enter it below to sign in.'),
            ],
          ),
        ),
        _RevealOnFocus(
          child: TextField(
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
              color: PTColors.fg,
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
                borderRadius: BorderRadius.circular(PTRadius.panel),
                borderSide: BorderSide(color: PTColors.white(0.15)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PTRadius.panel),
                borderSide: BorderSide(color: PTColors.white(0.15)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PTRadius.panel),
                borderSide: const BorderSide(color: PTColors.primary, width: 1.5),
              ),
            ),
            onChanged: (code) {
              if (code.trim().length == 6) {
                _verifyEmailOtp();
              }
            },
          ),
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
                color: _resendCooldown > 0 ? PTColors.white(0.4) : PTColors.link,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The marquee: "Take your seat." set big, with the full stop lit - the one
/// Beam on the page - over one plain line on what this is.
class _Marquee extends StatelessWidget {
  const _Marquee({required this.headlineSize, this.wordmark = false, this.brief = false});

  final double headlineSize;

  /// Phones: the one-line pitch, without the "movie night" lead-in.
  final bool brief;

  /// Landscape phones have no wordmark row of their own.
  final bool wordmark;

  @override
  Widget build(BuildContext context) {
    final headline = PTText.display.copyWith(
      fontSize: headlineSize,
      letterSpacing: -headlineSize * 0.05,
      height: 0.9,
    );
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        if (wordmark) ...[const PTWordmark(size: 18), const SizedBox(height: 22)],
        PTEntrance(child: Text('ADMIT ONE · TONIGHT', style: PTText.label)),
        SizedBox(height: headlineSize >= 100 ? 24 : 14),
        PTEntrance(
          delay: const Duration(milliseconds: 60),
          offset: 14,
          child: Text.rich(
            TextSpan(
              text: 'Take your\nseat',
              children: [
                TextSpan(
                  text: '.',
                  style: headline.copyWith(color: PTColors.primary),
                ),
              ],
            ),
            style: headline,
            // Display type is already large; at the body rate a 2x text
            // setting would turn the marquee into one word per line.
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.25),
          ),
        ),
        SizedBox(height: headlineSize >= 100 ? 28 : 18),
        PTEntrance(
          delay: const Duration(milliseconds: 120),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: headlineSize >= 100 ? 520 : 420),
            child: Text(
              brief
                  ? 'Bring a file or a YouTube link, and everyone presses play at the same moment.'
                  : 'Movie night with your people, wherever they are. Bring a file or a '
                        'YouTube link, and everyone presses play at the same moment.',
              style: PTText.body.copyWith(
                fontSize: headlineSize >= 100 ? 19 : 16,
                height: 1.5,
                color: PTColors.white(0.7),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A paper ticket at the foot of the desktop marquee. Decoration only - the
/// brand's highest-contrast object, on the page before you have a room.
class _AdmitOne extends StatelessWidget {
  const _AdmitOne();

  @override
  Widget build(BuildContext context) {
    return PTEntrance(
      delay: const Duration(milliseconds: 200),
      offset: 16,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: PTTicket(
            paper: true,
            stubWidth: 120,
            body: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
              child: Column(
                crossAxisAlignment: .start,
                spacing: 8,
                children: [
                  Text(
                    'ADMIT ONE · SCREEN 01',
                    style: PTText.label.copyWith(color: PTColors.canvas.withValues(alpha: 0.6)),
                  ),
                  Text(
                    'Your first night in',
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: PTText.cardHeading.copyWith(
                      color: PTColors.canvas,
                      fontSize: 24,
                      fontWeight: .w800,
                    ),
                  ),
                  Text(
                    'Free rooms seat 8 · voice chat included',
                    maxLines: 2,
                    style: PTText.caption.copyWith(color: PTColors.canvas.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            stub: Column(
              mainAxisAlignment: .center,
              spacing: 6,
              children: [
                Text(
                  'SEAT',
                  style: PTText.label.copyWith(color: PTColors.canvas.withValues(alpha: 0.6)),
                ),
                Text(
                  'A·01',
                  style: PTText.mono.copyWith(
                    fontSize: 22,
                    fontWeight: .w600,
                    color: PTColors.canvas,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The wordmark with the running version beside it (or at the far edge on a
/// phone). The version is quiet on purpose - it is for bug reports.
class _WordmarkRow extends StatelessWidget {
  const _WordmarkRow({this.spread = false, this.size = 22});

  final bool spread;
  final double size;

  @override
  Widget build(BuildContext context) {
    final version = AppVersion.current;
    return Row(
      mainAxisAlignment: spread ? .spaceBetween : .start,
      spacing: 16,
      children: [
        PTWordmark(size: size),
        if (version != null)
          Text(version, style: PTText.mono.copyWith(fontSize: 11, color: PTColors.away)),
      ],
    );
  }
}

/// Three plain facts beside the first-night ticket - what a free seat gets
/// you, in Cue ticks.
class _FirstNightChecks extends StatelessWidget {
  const _FirstNightChecks();

  static const _lines = [
    'Local files or YouTube',
    'Chat, reactions and voice',
    "Nobody starts till everyone's ready",
  ];

  @override
  Widget build(BuildContext context) {
    return PTEntrance(
      delay: const Duration(milliseconds: 260),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          spacing: 10,
          children: [
            for (final line in _lines)
              Row(
                crossAxisAlignment: .start,
                spacing: 10,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Symbols.check_rounded, size: 16, color: PTColors.online),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.8)),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Reprints Apple's own button as a Screen-paper slab: black becomes Screen
/// and white becomes Booth, so the mark, label and loader all invert while
/// the button keeps its official artwork, sizing and behaviour. Apple's
/// guidelines allow white and black styles alike.
class _PaperSlab extends StatelessWidget {
  const _PaperSlab({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const paper = PTColors.fg;
    const ink = PTColors.canvas;
    List<double> channel(double p, double i, int index) => [
      for (var k = 0; k < 3; k++) k == index ? i - p : 0,
      0,
      p * 255,
    ];
    return ColorFiltered(
      colorFilter: ColorFilter.matrix([
        ...channel(paper.r, ink.r, 0),
        ...channel(paper.g, ink.g, 1),
        ...channel(paper.b, ink.b, 2),
        // The slab is drawn at 88% black; lift it to opaque paper.
        0, 0, 0, 1.2, 0,
      ]),
      child: child,
    );
  }
}

/// A dashed rounded outline - the guest stub's "tear here" edge.
class _DashedOutline extends CustomPainter {
  const _DashedOutline({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.5));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) => old.color != color || old.radius != radius;
}

class _TermsNote extends StatelessWidget {
  const _TermsNote({this.align = .center});

  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final linkStyle = PTText.finePrint.copyWith(
      color: PTColors.link,
      decoration: TextDecoration.underline,
      decorationColor: PTColors.link.withValues(alpha: 0.6),
    );
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
      textAlign: align,
    );
  }
}

/// Scrolls an autofocused field into view once it takes focus.
///
/// EditableText only reveals its caret when the keyboard *changes* the
/// metrics; a field that autofocuses below the fold (2x text on a small
/// phone, or a keyboard already up from the previous view) would otherwise
/// sit focused under the nav bar or keyboard.
class _RevealOnFocus extends StatelessWidget {
  const _RevealOnFocus({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Scrollable.ensureVisible(context, alignment: 0.5);
        });
      },
      child: child,
    );
  }
}
