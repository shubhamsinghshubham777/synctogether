import 'package:flutter/material.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/mode_selection_dialog.dart';
import 'package:synctogether/ui/glass.dart';

void main() {
  group('ModeSelectionDialog', () {
    testWidgets('renders title, subtitle, and source options', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: ModeSelectionDialog())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('What are we watching?'), findsOneWidget);
      expect(find.text('Pick a source. Everyone stays in sync either way.'), findsOneWidget);
      expect(find.text('Local file'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.byIcon(BoothIcons.close), findsOneWidget);
    });

    testWidgets('selecting local file pops InitialMode.local', (tester) async {
      InitialMode? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showGlassDialog<InitialMode>(
                    context: context,
                    builder: (_) => const ModeSelectionDialog(),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Local file'));
      await tester.pumpAndSettle();

      expect(result, InitialMode.local);
    });

    testWidgets('selecting YouTube pops InitialMode.youtube', (tester) async {
      InitialMode? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showGlassDialog<InitialMode>(
                    context: context,
                    builder: (_) => const ModeSelectionDialog(),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('YouTube'));
      await tester.pumpAndSettle();

      expect(result, InitialMode.youtube);
    });

    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.iOS,
      TargetPlatform.android,
    ]) {
      testWidgets('on ${platform.name} the close button only closes the picker', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        InitialMode? result = InitialMode.local;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showGlassDialog<InitialMode>(
                      context: context,
                      builder: (_) => const ModeSelectionDialog(),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Close'), findsOneWidget, reason: 'a close icon says "Close"');
        expect(find.byTooltip('Leave room'), findsNothing);

        await tester.tap(find.byIcon(BoothIcons.close));
        await tester.pumpAndSettle();

        expect(find.text('Leave the room?'), findsNothing, reason: 'closing never asks to leave');
        expect(find.text('What are we watching?'), findsNothing, reason: 'the picker is gone');
        expect(result, isNull, reason: 'and nothing was chosen');
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('Esc closes the picker too, rather than asking to leave', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      InitialMode? result = InitialMode.youtube;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showGlassDialog<InitialMode>(
                    context: context,
                    builder: (_) => const ModeSelectionDialog(),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Leave the room?'), findsNothing);
      expect(find.text('What are we watching?'), findsNothing);
      expect(result, isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
