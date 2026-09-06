import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/loader.dart';

void main() {
  group('AppleButton', () {
    testWidgets('renders label and handles tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppleButton(label: 'Continue with Apple', onPressed: () => tapped = true),
            ),
          ),
        ),
      );

      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.byType(PTLoader), findsNothing);

      await tester.tap(find.byType(AppleButton));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('displays loader and ignores taps when loading', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppleButton(
                label: 'Continue with Apple',
                loading: true,
                onPressed: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PTLoader), findsOneWidget);
      expect(find.text('Continue with Apple'), findsNothing);

      await tester.tap(find.byType(AppleButton));
      await tester.pump();

      expect(tapped, isFalse);
    });
  });
}
