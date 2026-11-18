import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/ui/splash_screen.dart';

Widget _app({bool reduceMotion = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: const MaterialApp(
    home: PTSplash(child: Text('App Content', textDirection: TextDirection.ltr)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PTSplash', () {
    testWidgets('holds the app back, mounts it at the prewarm and hands off', (tester) async {
      await tester.pumpWidget(_app());
      expect(find.text('App Content'), findsNothing);

      // The clock starts on the first frame, with no audio gate in front of it.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('App Content'), findsNothing);

      // _kPrewarm is 1210 ms of 2400: the child is mounted before the fade starts.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('App Content'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('App Content'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('reduced motion holds, then only the hand-off fade plays', (tester) async {
      await tester.pumpWidget(_app(reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 16));

      // Already past the prewarm point: the child is mounted straight away.
      expect(find.text('App Content'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('App Content'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('tearing it down mid-hold leaves no pending timers', (tester) async {
      await tester.pumpWidget(_app(reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a restored launch skips straight to the app', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          restorationScopeId: 'app',
          home: PTSplash(child: Text('App Content', textDirection: TextDirection.ltr)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('App Content'), findsOneWidget);

      // The OS killed the app in the background and is restoring it.
      await tester.restartAndRestore();
      expect(find.text('App Content'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a fresh launch with no restoration data still plays it', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          restorationScopeId: 'app',
          home: PTSplash(child: Text('App Content', textDirection: TextDirection.ltr)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('App Content'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    test('the splash source uses no audio', () {
      final src = File('lib/ui/splash_screen.dart').readAsStringSync();
      expect(src, isNot(contains('media_kit')));
      expect(src, isNot(contains('Player')));
    });
  });
}
