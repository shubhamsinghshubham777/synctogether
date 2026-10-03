import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/popover.dart';

void main() {
  late PTPopoverHandle handle;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => handle = showPTPopover(
              context: context,
              builder: (_) => const Align(alignment: .topRight, child: Text('panel')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('panel'), findsOneWidget);
  }

  testWidgets('opens without pushing a route', (tester) async {
    await open(tester);
    expect(ModalRoute.of(tester.element(find.text('open')))!.isCurrent, isTrue);
  });

  testWidgets('a tap outside the panel closes it', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(20, 500));
    await tester.pumpAndSettle();
    expect(find.text('panel'), findsNothing);
    expect(handle.isOpen, isFalse);
  });

  testWidgets('Esc closes it', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('panel'), findsNothing);
  });

  testWidgets('close(animate: false) removes it on the same frame', (tester) async {
    await open(tester);
    handle.close(animate: false);
    await tester.pump();
    expect(find.text('panel'), findsNothing);
    await expectLater(handle.closed, completes);
  });
}
