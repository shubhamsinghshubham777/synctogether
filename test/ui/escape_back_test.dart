import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/escape_back.dart';

void main() {
  Widget host(Widget child, {required VoidCallback onBack}) => MaterialApp(
    home: PTEscapeBack(
      onBack: onBack,
      child: Scaffold(body: child),
    ),
  );

  testWidgets('Escape goes back', (tester) async {
    var backs = 0;
    await tester.pumpWidget(host(const SizedBox(), onBack: () => backs++));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(backs, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'first Escape in a text field only unfocuses it',
    (tester) async {
      var backs = 0;
      await tester.pumpWidget(host(const TextField(), onBack: () => backs++));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(backs, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(backs, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Escape closes a dialog without going back',
    (tester) async {
      var backs = 0;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (c) => TextButton(
              onPressed: () => showDialog<void>(
                context: c,
                builder: (_) => const AlertDialog(content: Text('hi')),
              ),
              child: const Text('open'),
            ),
          ),
          onBack: () => backs++,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('hi'), findsNothing);
      expect(backs, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
