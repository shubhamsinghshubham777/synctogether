import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/feedback/bug_report.dart';
import 'package:synctogether/feedback/contract.dart';
import 'package:synctogether/feedback/fake_feedback_service.dart';
import 'package:synctogether/feedback/feedback_services.dart';

import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/inputs.dart';

import '../../layout/layout_support.dart';
import '../../support/screen_matrix.dart';

/// A fake that also returns a (generated) screenshot and richer summary, and
/// lets a test decide what `submit` answers.
class _Service extends FakeFeedbackService {
  _Service({this.png, this.result, this.gatherGate, this.fileName});

  final Uint8List? png;
  final SubmitResult? result;
  final Completer<void>? gatherGate;

  /// What the media probe would have found for the playing film, if anything.
  final String? fileName;
  BugCapture? lastCapture;
  int submits = 0;
  bool? lastIncludeShot;
  BugCategory? lastCategory;
  String? lastNote;

  @override
  Future<BugCapture> captureScreen(BuildContext ctx) async =>
      BugCapture(screenshotPng: png, screenRoute: '/lobby/room/k7q2zp');

  @override
  Future<BugCapture> gather(BugCapture c) async {
    await gatherGate?.future;
    return c.copyWith(
      summary: {
        'app': '1.4.1 (88) · iOS 27.1',
        'screen': c.screenRoute,
        'sync': '±0.2 s · 4 seats · gate open',
        'net': 'wifi · rtt 38 ms · supabase ok',
      },
      logsText: 'sync.lock\nroom.join',
      fileName: fileName,
    );
  }

  @override
  Future<SubmitResult> submit(
    BugCapture c, {
    required BugCategory? category,
    String? note,
    required bool includeScreenshot,
  }) async {
    submits++;
    lastCapture = c;
    lastIncludeShot = includeScreenshot;
    lastCategory = category;
    lastNote = note;
    return result ??
        await super.submit(c, category: category, note: note, includeScreenshot: includeScreenshot);
  }
}

class _FlakyChoices extends _Service {
  _FlakyChoices({super.png});

  @override
  Future<void> setNotifyWhenFixed(String ref, bool on) async => throw StateError('flaky');
}

Future<Uint8List> _png() async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 90, 160), Paint()..color = const Color(0xFF3A332E));
  canvas.drawRect(const Rect.fromLTWH(10, 20, 70, 14), Paint()..color = const Color(0xFFFFB23F));
  final image = await rec.endRecording().toImage(90, 160);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  late Uint8List png;
  setUpAll(() async => png = (await _png()));
  setUp(BugReport.debugReset);
  tearDown(() => FeedbackServices.instance = FakeFeedbackService());

  Future<void> open(WidgetTester tester, _Service s) async {
    FeedbackServices.instance = s;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                TextButton(onPressed: () => BugReport.open(context), child: const Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  void wide(WidgetTester t) {
    t.view.physicalSize = const Size(1000, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('captures first, sends category + note, shows the code', (tester) async {
    wide(tester);
    final s = _Service(png: png);
    await open(tester, s);
    expect(find.text('Send report'), findsOneWidget);
    await tester.tap(find.text('Video'));
    await tester.enterText(find.byType(TextField), 'Screen went black');
    await tester.tap(find.text('Send report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(s.submits, 1);
    expect(s.lastCategory, BugCategory.video);
    expect(s.lastNote, 'Screen went black');
    expect(s.lastIncludeShot, isTrue);
    expect(find.text("Thanks. We've got it."), findsOneWidget);
    expect(find.text('BUG-0001'), findsOneWidget);
  });

  testWidgets('a category is optional and tapping it again clears it', (tester) async {
    wide(tester);
    final s = _Service(png: png);
    await open(tester, s);
    await tester.tap(find.text('Sync'));
    await tester.pump();
    await tester.tap(find.text('Sync'));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(s.lastCategory, isNull);
    expect(s.lastNote, isNull);
  });

  testWidgets('the disclosure lists what is sent and the screenshot can be dropped', (
    tester,
  ) async {
    wide(tester);
    final s = _Service(png: png);
    await open(tester, s);
    await tester.tap(find.text('See exactly what we send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('rtt 38 ms', findRichText: true), findsOneWidget);
    await tester.tap(find.byType(PTToggleRow), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.byType(PTButton), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(s.lastIncludeShot, isFalse);
  });

  group('the video file name', () {
    const name = 'Some.Film.2024.2160p.mkv';
    final fileSwitch = find.text("Include the video's file name");

    Future<void> openDisclosure(WidgetTester tester) async {
      await tester.tap(find.text('See exactly what we send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> send(WidgetTester tester) async {
      await tester.tap(find.byType(PTButton).first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('no switch when no film is playing', (tester) async {
      wide(tester);
      await open(tester, _Service(png: png));
      await openDisclosure(tester);
      expect(fileSwitch, findsNothing);
    });

    testWidgets('off by default: the name is neither listed nor sent', (tester) async {
      wide(tester);
      final s = _Service(png: png, fileName: name);
      await open(tester, s);
      await openDisclosure(tester);
      expect(fileSwitch, findsOneWidget);
      expect(find.textContaining(name, findRichText: true), findsNothing);
      await send(tester);
      expect(s.lastCapture!.includeFileName, isFalse);
      expect(s.lastCapture!.fileNameToSend, isNull);
    });

    testWidgets('switching it on lists the line and sends exactly that', (tester) async {
      wide(tester);
      final s = _Service(png: png, fileName: name);
      await open(tester, s);
      await openDisclosure(tester);
      await tester.ensureVisible(fileSwitch);
      await tester.tap(fileSwitch);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining(name, findRichText: true), findsOneWidget);
      await send(tester);
      expect(s.lastCapture!.includeFileName, isTrue);
      expect(s.lastCapture!.fileNameToSend, name);
    });

    testWidgets('switching it back off takes the name out again', (tester) async {
      wide(tester);
      final s = _Service(png: png, fileName: name);
      await open(tester, s);
      await openDisclosure(tester);
      await tester.ensureVisible(fileSwitch);
      await tester.tap(fileSwitch);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(fileSwitch);
      await tester.pump(const Duration(milliseconds: 600));
      await send(tester);
      expect(s.lastCapture!.fileNameToSend, isNull);
    });

    testWidgets('a fresh sheet starts with it off again', (tester) async {
      wide(tester);
      final s = _Service(png: png, fileName: name);
      await open(tester, s);
      await openDisclosure(tester);
      await tester.ensureVisible(fileSwitch);
      await tester.tap(fileSwitch);
      await tester.pump(const Duration(milliseconds: 600));
      // Close it without sending, then open a new one.
      await tester.tap(find.byTooltip('Close'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));
      BugReport.debugReset();
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await openDisclosure(tester);
      expect(find.textContaining(name, findRichText: true), findsNothing);
      await send(tester);
      expect(s.lastCapture!.fileNameToSend, isNull);
    });
  });

  testWidgets('offline: the saved state, nothing implied sent', (tester) async {
    wide(tester);
    final s = _Service(png: png, result: const Queued('local-1'));
    await open(tester, s);
    await tester.tap(find.text('Send report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Saved on this device.'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('rate limited: friendly line, form stays', (tester) async {
    wide(tester);
    final s = _Service(png: png, result: const RateLimited(Duration(seconds: 20)));
    await open(tester, s);
    await tester.tap(find.text('Send report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('20 seconds'), findsOneWidget);
    expect(find.text('Send report'), findsOneWidget);
  });

  testWidgets('send waits briefly for the slow data, never blocks on it for ever', (tester) async {
    final gate = Completer<void>();
    wide(tester);
    final s = _Service(png: png, gatherGate: gate);
    await open(tester, s);
    await tester.tap(find.text('Send report'));
    await tester.pump(const Duration(seconds: 1));
    expect(s.submits, 0, reason: 'still gathering');
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));
    expect(s.submits, 1, reason: 'gives up waiting after 3 s');
    gate.complete();
    await tester.pump();
  });

  testWidgets('after sending: notify is on, can be switched off, details can be added', (
    tester,
  ) async {
    wide(tester);
    final s = _Service(png: png);
    await open(tester, s);
    await tester.tap(find.text('Send report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("Tell me when it's fixed"), findsOneWidget);
    expect(s.notifyChoices['BUG-0001'], isTrue);

    await tester.tap(find.text("Tell me when it's fixed"));
    await tester.pump();
    expect(s.notifyChoices['BUG-0001'], isFalse);

    await tester.tap(find.text('Add more details'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'It was the second film.');
    // The dialog scrolls; press the button itself rather than hunt for it.
    tester.widget<PTButton>(find.widgetWithText(PTButton, 'Add to my report')).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.appended['BUG-0001'], ['It was the second film.']);
    expect(find.text('Added to your report. Thank you.'), findsOneWidget);
    expect(find.text('Add more details'), findsNothing);
  });

  testWidgets('a saved-offline report talks about its local id', (tester) async {
    wide(tester);
    final s = _Service(png: png, result: const Queued('local-1'));
    await open(tester, s);
    await tester.tap(find.text('Send report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text("Tell me when it's fixed"));
    await tester.pump();
    await tester.tap(find.text('Add more details'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'more');
    // The dialog scrolls; press the button itself rather than hunt for it.
    tester.widget<PTButton>(find.widgetWithText(PTButton, 'Add to my report')).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.notifyChoices['local-1'], isFalse);
    expect(s.appended['local-1'], ['more']);
  });

  testWidgets('a choice that fails to save flips back and says so', (tester) async {
    wide(tester);
    final s = _FlakyChoices(png: png);
    await open(tester, s);
    await tester.tap(find.text('Send report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text("Tell me when it's fixed"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The cause leaves by the diagnostics door; the user gets friendly copy.
    expect(tester.takeException(), isA<StateError>());
    expect(find.textContaining("didn't save"), findsOneWidget);
  });

  testWidgets('a follow-up names the earlier report and carries it in the context', (tester) async {
    wide(tester);
    final s = _Service(png: png);
    FeedbackServices.instance = s;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => BugReport.open(context, source: 'reports', followUpOf: 'BUG-1C0D'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Following up on BUG-1C0D: '), findsOneWidget);
    await tester.tap(find.text('Send report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(s.submitted.last.context['follow_up_of'], 'BUG-1C0D');
    expect(s.lastNote, 'Following up on BUG-1C0D:');
  });

  group('layout matrix', () {
    for (final name in ['collecting', 'disclosure', 'filename', 'sent']) {
      screenMatrix('bug-report/$name', (tester, c, scale) async {
        final s = _Service(
          png: png,
          gatherGate: name == 'collecting' ? Completer() : null,
          fileName: name == 'filename' ? 'Some.Film.2024.2160p.mkv' : null,
        );
        FeedbackServices.instance = s;
        await pumpDialogOpener(tester, c, scale, (ctx) => BugReport.open(ctx));
        if (name == 'disclosure' || name == 'filename') {
          await tester.ensureVisible(find.text('See exactly what we send'));
          await tester.tap(find.text('See exactly what we send'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump(const Duration(milliseconds: 600));
        }
        if (name == 'filename') {
          final sw = find.text("Include the video's file name");
          await tester.ensureVisible(sw);
          await tester.tap(sw);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump(const Duration(milliseconds: 600));
        }
        if (name == 'sent') {
          await tester.ensureVisible(find.text('Send report'));
          await tester.tap(find.text('Send report'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pump(const Duration(milliseconds: 700));
        }
        await finishCase(tester);
      });
    }
  });
}
