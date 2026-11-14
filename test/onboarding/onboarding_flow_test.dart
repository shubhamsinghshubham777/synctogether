import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/onboarding/onboarding_flow.dart';
import 'package:synctogether/onboarding/onboarding_logic.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/ui/pt_theme.dart';

const _maya = Profile(id: 'u1', displayName: 'Maya', isGuest: false, authProvider: 'google');
const _guest = Profile(id: 'u2', displayName: 'Guest-a1b2', isGuest: true);

/// Opens the flow; whatever it returns lands in [results].
Future<void> _open(
  WidgetTester tester,
  List<OnboardingResult> results, {
  Profile profile = _maya,
  String? invite,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildPTTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              results.add(await showOnboarding(context, profile: profile, inviteCode: invite)),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tapAndSettle(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('partner path: name, then path, returns both', (tester) async {
    final out = <OnboardingResult>[];
    await _open(tester, out);
    expect(find.text('What name goes on your ticket?'), findsOneWidget);
    expect(find.text('Filled in from Google. Change it any time in Profile.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Maya O  ');
    await _tapAndSettle(tester, "That's me");
    expect(find.text("Who's watching with you?"), findsOneWidget);
    await _tapAndSettle(tester, pathTitle(OnboardingPath.partner));
    await _tapAndSettle(tester, 'Continue');
    expect(out.single.name, 'Maya O');
    expect(out.single.path, OnboardingPath.partner);
    expect(out.single.skipped, isFalse);
  });

  testWidgets('Skip on the first step keeps the current name', (tester) async {
    final out = <OnboardingResult>[];
    await _open(tester, out);
    await tester.enterText(find.byType(TextField), 'Somebody else');
    await _tapAndSettle(tester, 'Skip');
    expect(out.single.skippedAt, OnboardingStep.name);
    expect(out.single.name, isNull);
  });

  testWidgets('an empty name shows friendly copy and stays put', (tester) async {
    await _open(tester, <OnboardingResult>[]);
    await tester.enterText(find.byType(TextField), '   ');
    await _tapAndSettle(tester, "That's me");
    expect(find.text('Your ticket needs a name.'), findsOneWidget);
    expect(find.text('What name goes on your ticket?'), findsOneWidget);
  });

  testWidgets('guests start with an empty field and no partner option', (tester) async {
    await _open(tester, <OnboardingResult>[], profile: _guest);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    await tester.enterText(find.byType(TextField), 'Sam');
    await _tapAndSettle(tester, "That's me");
    expect(find.text(pathTitle(OnboardingPath.partner)), findsNothing);
    expect(find.text(pathTitle(OnboardingPath.friends)), findsOneWidget);
  });

  testWidgets('an invite asks only for the name', (tester) async {
    final out = <OnboardingResult>[];
    await _open(tester, out, invite: 'K7Q2ZP');
    expect(find.text('Someone saved you a seat.'), findsOneWidget);
    expect(find.text('K7Q2ZP'), findsOneWidget);
    await _tapAndSettle(tester, 'Take your seat');
    expect(out.single.path, isNull);
    expect(out.single.name, 'Maya');
  });

  testWidgets('wide windows get the panel with a Back link on step 2', (tester) async {
    await _open(tester, <OnboardingResult>[], size: const Size(1280, 800));
    expect(find.text('Back'), findsNothing);
    await _tapAndSettle(tester, "That's me");
    expect(find.text('Back'), findsOneWidget);
    await _tapAndSettle(tester, 'Back');
    expect(find.text('What name goes on your ticket?'), findsOneWidget);
  });
}
