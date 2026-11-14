import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/profile_shortcut.dart';

/// Cmd+, is the macOS app menu's (native item, over a channel); Ctrl+, is a
/// plain key binding everywhere else. Exactly one is live per platform.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<int> run(WidgetTester tester, TargetPlatform platform, Future<void> Function() act) async {
    debugDefaultTargetPlatformOverride = platform;
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileShortcut(
          open: () => opened++,
          child: const Scaffold(body: Focus(autofocus: true, child: SizedBox.expand())),
        ),
      ),
    );
    await tester.pump();
    await act();
    debugDefaultTargetPlatformOverride = null;
    return opened;
  }

  Future<void> menu() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        ProfileShortcut.menuChannel.name,
        ProfileShortcut.menuChannel.codec.encodeMethodCall(const MethodCall('open')),
        (_) {},
      );

  testWidgets('macOS: the app menu opens it, the key is left to AppKit', (tester) async {
    final n = await run(tester, .macOS, () async {
      await tester.sendKeyDownEvent(.metaLeft);
      await tester.sendKeyEvent(.comma);
      await tester.sendKeyUpEvent(.metaLeft);
      await menu();
    });
    expect(n, 1);
  });

  testWidgets('Windows: Ctrl+, opens it', (tester) async {
    final n = await run(tester, .windows, () async {
      await tester.sendKeyDownEvent(.controlLeft);
      await tester.sendKeyEvent(.comma);
      await tester.sendKeyUpEvent(.controlLeft);
    });
    expect(n, 1);
  });
}
