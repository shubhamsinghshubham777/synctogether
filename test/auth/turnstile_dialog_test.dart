import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/auth/turnstile_dialog.dart';
import 'package:synctogether/auth/webview_runtime.dart';
import 'package:synctogether/ui/buttons.dart';

void main() {
  group('TurnstileDialog', () {
    tearDown(() {
      PTWebView.runtimeMissing = false;
    });

    testWidgets('shows download button and error message when runtime is missing', (tester) async {
      PTWebView.runtimeMissing = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showTurnstileDialog(context),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Quick check'), findsOneWidget);
      expect(find.text('Error webview2-missing'), findsOneWidget);
      expect(find.text('Download WebView2 Runtime'), findsOneWidget);
      expect(find.widgetWithText(PTButton, 'Close'), findsOneWidget);

      // Tapping Close dismisses the dialog
      await tester.tap(find.widgetWithText(PTButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.text('Quick check'), findsNothing);
    });
  });
}
