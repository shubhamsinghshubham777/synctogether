import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/auth/login_screen.dart';
import 'package:synctogether/ui/buttons.dart';

import 'package:synctogether/ui/responsive.dart';

void main() {
  group('LoginScreen', () {
    testWidgets('renders auth providers and toggles email view', (tester) async {
      await tester.pumpWidget(
        MaterialApp(builder: buildResponsiveWrapper, home: const LoginScreen()),
      );
      // Allow entrance transitions to settle
      await tester.pump(const Duration(milliseconds: 400));

      // Verify initial providers view
      if (AuthService.instance.isAppleSupported) {
        expect(find.byType(AppleButton), findsOneWidget);
      }
      expect(find.byType(GoogleButton), findsOneWidget);
      expect(find.text('Continue with email'), findsOneWidget);
      expect(find.text('Continue as guest'), findsOneWidget);

      // Tap 'Continue with email'
      await tester.tap(find.text('Continue with email'));
      await tester.pump(const Duration(milliseconds: 400));

      // Verify email input view. Both routes in are offered side by side:
      // a password for accounts that set one, and a code for everyone else.
      expect(find.text('Sign in with email'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Email me a 6-digit code'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));

      // Tap back arrow to return to providers
      await tester.tap(find.byIcon(Symbols.arrow_back_rounded));
      await tester.pump(const Duration(milliseconds: 400));

      // Verify returned to providers view
      expect(find.byType(GoogleButton), findsOneWidget);
      expect(find.text('Continue with email'), findsOneWidget);
    });

    testWidgets('password starts hidden and the eye reveals it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(builder: buildResponsiveWrapper, home: const LoginScreen()),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Continue with email'));
      await tester.pump(const Duration(milliseconds: 400));

      TextField passwordField() => tester.widgetList<TextField>(find.byType(TextField)).last;

      expect(passwordField().obscureText, isTrue);

      await tester.tap(find.byIcon(Symbols.visibility_rounded));
      await tester.pump();

      expect(passwordField().obscureText, isFalse);
      expect(find.byIcon(Symbols.visibility_off_rounded), findsOneWidget);
    });
  });
}
