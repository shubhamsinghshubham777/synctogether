import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/reactions.dart';
import 'package:synctogether/rooms/widgets/reaction_overlay.dart';
import 'package:synctogether/rooms/widgets/reaction_strip.dart';

void main() {
  group('ReactionPickerDialog', () {
    testWidgets('can be opened and closed without deactivated widget error', (tester) async {
      final assets = ReactionAssets();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog<PTReaction>(
                    context: context,
                    builder: (ctx) =>
                        ReactionPickerDialog(reactions: kAllReactions, assets: assets),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();

      // Close the dialog without interacting with every emoji cell
      Navigator.of(tester.element(find.byType(ReactionPickerDialog))).pop();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'hovering or tapping an item initializes animation controller and disposes cleanly',
      (tester) async {
        final assets = ReactionAssets();
        PTReaction? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    selected = await showDialog<PTReaction>(
                      context: context,
                      builder: (ctx) =>
                          ReactionPickerDialog(reactions: kAllReactions, assets: assets),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Tap on the first reaction in the picker
        final firstReaction = kAllReactions.first;
        await tester.tap(find.text(firstReaction.emoji));
        await tester.pumpAndSettle();

        expect(selected, equals(firstReaction));
      },
    );
  });

  group('ReactionStrip', () {
    testWidgets('mounts and disposes cleanly when closed and opened', (tester) async {
      final assets = ReactionAssets();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionStrip(open: true, assets: assets, onPick: (_) {}),
          ),
        ),
      );
      await tester.pump();

      // Unmount the ReactionStrip
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
      await tester.pumpAndSettle();
    });
  });
}
