import 'package:flutter/material.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/rolling_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/our_room_media.dart';
import 'package:synctogether/rooms/widgets/media_sharing_prompt_dialog.dart';
import 'package:synctogether/rooms/widgets/sharing_progress_indicator.dart';

/// A rolling line (the percentage), found by the whole string it shows.
Finder _rolling(String t) => find.byWidgetPredicate((w) => w is PTRollingText && w.text == t);

void main() {
  group('SharingProgressIndicator', () {
    testWidgets('renders progress percentage, speed and ETA', (tester) async {
      var cancelTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SharingProgressIndicator(
              fraction: 0.45,
              speedBps: 2.5 * 1024 * 1024, // 2.5 MB/s
              etaSeconds: 85,
              state: 'uploading',
              label: 'Uploading video...',
              onCancel: () => cancelTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Uploading video...'), findsOneWidget);
      expect(_rolling('45%'), findsOneWidget);
      expect(find.textContaining('2.5 MB/s'), findsOneWidget);
      expect(find.textContaining('1m 25s'), findsOneWidget);

      await tester.tap(find.byIcon(BoothIcons.close));
      expect(cancelTapped, isTrue);
    });

    testWidgets('renders completed state when fraction is 1.0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SharingProgressIndicator(
              fraction: 1.0,
              speedBps: 0,
              etaSeconds: 0,
              state: 'ready',
              label: 'Ready to watch',
            ),
          ),
        ),
      );

      expect(find.text('Ready to watch'), findsOneWidget);
      expect(_rolling('100%'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });

  group('MediaSharingPromptDialog', () {
    testWidgets('returns share selection and remember choice', (tester) async {
      MediaSharingPromptResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showMediaSharingPromptDialog(
                    context: context,
                    fileName: 'vacation.mp4',
                    fileSize: 150 * 1024 * 1024,
                  );
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Share with the room?'), findsOneWidget);
      expect(find.textContaining('vacation.mp4'), findsOneWidget);
      expect(find.textContaining('150 MB'), findsOneWidget);

      // Check remember checkbox
      await tester.tap(find.byType(PTCheckTile));
      await tester.pumpAndSettle();

      // Tap "Share with room"
      await tester.tap(find.text('Share with room'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.shouldShare, isTrue);
      expect(result!.rememberChoice, isTrue);
    });

    Future<void> openWith(WidgetTester tester, {String? keepNote}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMediaSharingPromptDialog(
                context: context,
                fileName: 'film.mkv',
                fileSize: 150 * 1024 * 1024,
                keepNote: keepNote,
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
    }

    testWidgets('an ordinary room says the upload goes when the room closes', (tester) async {
      await openWith(tester);
      expect(find.textContaining("It's removed when the room closes."), findsOneWidget);
    });

    testWidgets('Our Room says how long it is kept instead, and not the old promise', (
      tester,
    ) async {
      await openWith(tester, keepNote: ourRoomKeepNote(patron: false));
      expect(find.textContaining('36 hours after your session'), findsOneWidget);
      expect(find.textContaining('removed when the room closes'), findsNothing);
    });

    testWidgets('returns local only selection', (tester) async {
      MediaSharingPromptResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showMediaSharingPromptDialog(
                    context: context,
                    fileName: 'movie.mkv',
                    fileSize: 500 * 1024 * 1024,
                  );
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Play locally'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.shouldShare, isFalse);
      expect(result!.rememberChoice, isFalse);
    });
  });
}
