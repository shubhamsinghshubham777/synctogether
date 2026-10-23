import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    testWidgets('a non-Apple build neither sells nor points anywhere that does', (tester) async {
      await tester.pumpWidget(_wrap(const SubscriptionScreen(appleStoreBuildOverride: false)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Take a Patron seat'), findsNothing);
      expect(find.textContaining('synctogether.app'), findsNothing);
      expect(find.textContaining('website'), findsNothing);
      expect(find.textContaining('Patron seats are sold in the App Store apps'), findsWidgets);
    });

    testWidgets('a Microsoft Store build sells through the Store and never steers to a website', (
      tester,
    ) async {
      // The native Store plugin is absent under flutter test; answer "no products",
      // which is now reported, so swallow the report here.
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = previousOnError);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('app.synctogether/store_purchase'),
        (call) async => <Object?>[],
      );
      await tester.pumpWidget(
        _wrap(
          const SubscriptionScreen(
            appleStoreBuildOverride: false,
            microsoftStoreBuildOverride: true,
            canSellOverride: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Patron seats'), findsOneWidget);
      expect(find.textContaining('website'), findsNothing);
      expect(find.text("Couldn't reach the Microsoft Store right now."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // flutter test is a debug build, so the developer line shows here only.
      expect(find.text('The Store returned no subscriptions for this app.'), findsOneWidget);
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
