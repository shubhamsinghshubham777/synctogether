import 'package:flutter/material.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/subscription_screen.dart';
import 'package:synctogether/ui/responsive.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    builder: buildResponsiveWrapper,
    home: Scaffold(body: child),
  );
}

void main() {
  group('SubscriptionScreen', () {
    testWidgets('desktop renders the Patron checkout button for free users on non-store build', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const SubscriptionScreen(desktopOverride: true, storeBuildOverride: false)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Patron seats'), findsOneWidget);
      expect(find.text('Take a Patron seat'), findsOneWidget);
      expect(find.text('Checkout opens on synctogether.app in your browser.'), findsOneWidget);
      expect(find.byIcon(BoothIcons.crown), findsWidgets);
    });

    testWidgets('desktop store build hides the checkout button and shows compliant info banner', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const SubscriptionScreen(desktopOverride: true, storeBuildOverride: true)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Patron seats'), findsOneWidget);
      expect(find.text('Take a Patron seat'), findsNothing);
      expect(find.text('Subscriptions are managed on our website.'), findsOneWidget);
      expect(find.text('Refresh status'), findsOneWidget);
    });

    testWidgets('mobile renders plain text info instead of button', (tester) async {
      await tester.pumpWidget(_wrap(const SubscriptionScreen(desktopOverride: false)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Patron seats'), findsOneWidget);
      expect(find.text('Take a Patron seat'), findsNothing);
      expect(find.text('Subscriptions are managed on our website.'), findsOneWidget);
      expect(find.text('Refresh status'), findsOneWidget);
    });

    testWidgets('apple store build sells through the App Store and never steers to the website', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SubscriptionScreen(
            desktopOverride: true,
            storeBuildOverride: true,
            appleStoreBuildOverride: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Patron seats'), findsOneWidget);
      expect(find.text('Take a Patron seat'), findsNothing);
      expect(find.text('Subscriptions are managed on our website.'), findsNothing);
      expect(find.textContaining('website'), findsNothing);
      expect(find.text("Couldn't reach the App Store right now."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
