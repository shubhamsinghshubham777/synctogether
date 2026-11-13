import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/feedback/bug_report.dart';
import 'package:synctogether/feedback/fake_feedback_service.dart';
import 'package:synctogether/feedback/feedback_services.dart';
import 'package:synctogether/feedback/shortcuts.dart';

/// The two desktop doors to "Report a bug": the macOS Help menu (native item,
/// over a channel) and Ctrl+Shift+B everywhere else. Exactly one of them is
/// live per platform, so one press can never open two sheets.
void main() {
  late FakeFeedbackService service;
  BuildContext? navigator;

  setUp(() {
    service = FakeFeedbackService();
    FeedbackServices.instance = service;
    navigator = null;
    BugReport.debugReset();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    BugReport.debugReset();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            navigator = context;
            return BugReportShortcut(
              navigatorContext: () => navigator,
              child: const Scaffold(body: Focus(autofocus: true, child: SizedBox.expand())),
            );
          },
        ),
      ),
    );
    await tester.pump();
  }

  /// Flutter checks the platform override is unset before `tearDown` runs, so it
  /// is cleared here, inside the test body.
  Future<void> on(TargetPlatform platform, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> menuReport() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        BugReportShortcut.menuChannel.name,
        BugReportShortcut.menuChannel.codec.encodeMethodCall(const MethodCall('report')),
        (_) {},
      );

  testWidgets('macOS: the Help menu item opens the sheet', (tester) async {
    await on(.macOS, () async {
      await pump(tester);
      expect(BugReport.isOpen, isFalse);

      await menuReport();
      await tester.pump();

      expect(BugReport.isOpen, isTrue);
    });
  });

  testWidgets('macOS: Shift+Cmd+B is left to the menu, so the shortcut does not also open it', (
    tester,
  ) async {
    await on(.macOS, () async {
      await pump(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(BugReport.isOpen, isFalse);
    });
  });

  testWidgets(
    'macOS: a remount keeps answering the menu (the old state is disposed after the new one)',
    (tester) async {
      await on(.macOS, () async {
        Widget app(Key key) => MaterialApp(
          home: Builder(
            builder: (context) {
              navigator = context;
              return BugReportShortcut(
                key: key,
                navigatorContext: () => navigator,
                child: const Scaffold(body: SizedBox.expand()),
              );
            },
          ),
        );

        await tester.pumpWidget(app(const ValueKey('a')));
        // Same position, new key: the new state is created, then the old is disposed.
        await tester.pumpWidget(app(const ValueKey('b')));

        await menuReport();
        await tester.pump();

        expect(BugReport.isOpen, isTrue);
      });
    },
  );

  testWidgets('macOS: a menu press before the navigator exists does nothing', (tester) async {
    await on(.macOS, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: BugReportShortcut(
            navigatorContext: () => null,
            child: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      );

      await menuReport();
      await tester.pump();

      expect(BugReport.isOpen, isFalse);
    });
  });

  testWidgets('Windows: Ctrl+Shift+B opens the sheet, and the menu channel is not listened to', (
    tester,
  ) async {
    await on(.windows, () async {
      await pump(tester);

      await menuReport();
      await tester.pump();
      expect(BugReport.isOpen, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(BugReport.isOpen, isTrue);
    });
  });
}
