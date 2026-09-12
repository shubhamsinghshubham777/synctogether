import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
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
      expect(find.text('Pick a source - everyone stays in sync either way.'), findsOneWidget);
      expect(find.text('Local file'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.byIcon(Symbols.close_rounded), findsOneWidget);
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

    testWidgets('close button prompts leave confirmation; Stay keeps dialog open', (tester) async {
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

      // Tap close button
      await tester.tap(find.byIcon(Symbols.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Leave room?'), findsOneWidget);
      expect(
        find.text('Are you sure you want to leave this room? You will return to the lobby.'),
        findsOneWidget,
      );

      // Tap Stay
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();

      // Dialog is still open, result is still null
      expect(find.text('What are we watching?'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('close button prompts leave confirmation; Leave room pops InitialMode.leave', (
      tester,
    ) async {
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

      // Tap close button
      await tester.tap(find.byIcon(Symbols.close_rounded));
      await tester.pumpAndSettle();

      // Tap Leave room
      await tester.tap(find.text('Leave room'));
      await tester.pumpAndSettle();

      expect(result, InitialMode.leave);
    });

    testWidgets('pressing ESC key triggers leave confirmation', (tester) async {
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

      // Send ESC key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Leave room?'), findsOneWidget);

      // Tap Leave room
      await tester.tap(find.text('Leave room'));
      await tester.pumpAndSettle();

      expect(result, InitialMode.leave);
    });
  });
}
