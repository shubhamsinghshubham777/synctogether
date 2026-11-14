import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/pairing/pair_widgets.dart';
import 'package:synctogether/ui/pt_theme.dart';

void main() {
  tearDown(() {
    Env.resetOverridesForTesting();
    debugDefaultTargetPlatformOverride = null;
  });

  void releaseWithSite(String? url) {
    Env.overrideReleaseMode = true;
    Env.overrideSiteUrl = url ?? '';
  }

  test('shows on a platform that has the app, when the build has a website', () {
    releaseWithSite('https://watch.example.com');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(showsAndroidNudge, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(showsAndroidNudge, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(showsAndroidNudge, isTrue);
  });

  test('hidden on Android itself: the reader is already on the platform', () {
    releaseWithSite('https://watch.example.com');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(showsAndroidNudge, isFalse);
  });

  test('hidden when the build has no website to open (a fork with no SITE_URL)', () {
    releaseWithSite(null);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(showsAndroidNudge, isFalse);
  });

  testWidgets('says what it does and is a real button', (tester) async {
    releaseWithSite('https://watch.example.com');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // Before the framework's own check that no debug variable was left changed.
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPTTheme(),
        home: const Scaffold(body: PairAndroidNudge()),
      ),
    );
    expect(find.bySemanticsLabel('Partner on Android? Save them a test seat'), findsOneWidget);
    expect(tester.getSize(find.byType(PairAndroidNudge)).height, greaterThanOrEqualTo(44));
  });
}
