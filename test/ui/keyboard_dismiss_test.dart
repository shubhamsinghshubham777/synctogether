import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/keyboard_dismiss.dart';

/// A short screen: a field and a button at the top, a lot of nothing below.
/// `testWidgets` for [p]. The override has to be cleared inside the test body:
/// a tearDown runs after the binding has already checked it.
void _testOn(TargetPlatform p, String name, Future<void> Function(WidgetTester) body) {
  testWidgets('on $p $name', (tester) async {
    debugDefaultTargetPlatformOverride = p;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Widget _app({required FocusNode field, required FocusNode button, VoidCallback? onPressed}) {
  return MaterialApp(
    builder: (context, child) => TapToDismissKeyboard(child: child!),
    home: Scaffold(
      body: Column(
        children: [
          // Flutter's own desktop default (onTapOutside) unfocuses on a click away; it is
          // silenced so the test isolates what TapToDismissKeyboard adds.
          TextField(focusNode: field, onTapOutside: (_) {}),
          TextButton(focusNode: button, onPressed: onPressed ?? () {}, child: const Text('Go')),
          const SizedBox(height: 40, child: Text('label')),
        ],
      ),
    ),
  );
}

const _empty = Offset(200, 500);

void main() {
  for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('touch $p', () {
      late FocusNode field;
      late FocusNode button;
      setUp(() {
        field = FocusNode();
        button = FocusNode();
      });
      tearDown(() {
        field.dispose();
        button.dispose();
      });

      _testOn(p, 'a tap on empty space unfocuses the field', (tester) async {
        await tester.pumpWidget(_app(field: field, button: button));
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(field.hasPrimaryFocus, isTrue);
        await tester.tapAt(_empty);
        await tester.pump();
        expect(field.hasFocus, isFalse);
      });

      _testOn(p, 'a tap on the field itself keeps focus', (tester) async {
        await tester.pumpWidget(_app(field: field, button: button));
        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(field.hasPrimaryFocus, isTrue);
      });

      _testOn(p, 'a button still fires and does not close the keyboard', (tester) async {
        var pressed = 0;
        await tester.pumpWidget(_app(field: field, button: button, onPressed: () => pressed++));
        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.tap(find.text('Go'));
        await tester.pump();
        expect(pressed, 1);
        expect(field.hasPrimaryFocus, isTrue);
      });

      _testOn(p, 'focus that is not a text field is left alone', (tester) async {
        await tester.pumpWidget(_app(field: field, button: button));
        button.requestFocus();
        await tester.pump();
        await tester.tapAt(_empty);
        await tester.pump();
        expect(button.hasPrimaryFocus, isTrue);
      });

      _testOn(p, 'a drag does not dismiss', (tester) async {
        await tester.pumpWidget(_app(field: field, button: button));
        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.dragFrom(_empty, const Offset(0, -80));
        await tester.pump();
        expect(field.hasPrimaryFocus, isTrue);
      });

      _testOn(p, 'a dialog barrier tap closes the dialog and the keyboard', (tester) async {
        await tester.pumpWidget(_app(field: field, button: button));
        final context = tester.element(find.byType(Scaffold));
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: SizedBox(height: 40, child: Text('hi'))),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('hi'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('hi'), findsNothing);
      });
    });
  }

  for (final p in [TargetPlatform.macOS, TargetPlatform.windows]) {
    _testOn(p, 'a click on empty space keeps focus', (tester) async {
      final field = FocusNode();
      final button = FocusNode();
      addTearDown(field.dispose);
      addTearDown(button.dispose);
      await tester.pumpWidget(_app(field: field, button: button));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tapAt(_empty);
      await tester.pump();
      expect(field.hasPrimaryFocus, isTrue);
    });
  }
}
