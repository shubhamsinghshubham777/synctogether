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
    testWidgets('every non-Apple build sells through the web checkout', (tester) async {
      await tester.pumpWidget(_wrap(const SubscriptionScreen(appleStoreBuildOverride: false)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Patron seats'), findsOneWidget);
      expect(find.text('Take a Patron seat'), findsWidgets);
      expect(find.text('Checkout opens on synctogether.app in your browser.'), findsWidgets);
      expect(find.text('Subscriptions are managed on our website.'), findsNothing);
      expect(find.byIcon(BoothIcons.crown), findsWidgets);
    });

    testWidgets('a Google Play build neither sells nor points anywhere that does', (tester) async {
      await tester.pumpWidget(
        _wrap(const SubscriptionScreen(appleStoreBuildOverride: false, canSellOverride: false)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Take a Patron seat'), findsNothing);
      expect(find.textContaining('synctogether.app'), findsNothing);
      expect(find.textContaining('website'), findsNothing);
      expect(find.text("Patron seats aren't available in this version of the app."), findsWidgets);
    });

    testWidgets('apple store build sells through the App Store and never steers to the website', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SubscriptionScreen(appleStoreBuildOverride: true)));
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
