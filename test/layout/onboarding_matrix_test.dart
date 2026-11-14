import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/onboarding/onboarding_coach.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/coach_target.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/onboarding/onboarding_flow.dart';
import 'package:synctogether/profile/profile_models.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

const _maya = Profile(
  id: '7d1f0c2e-0000-4000-8000-000000000001',
  displayName: 'Maya Okafor',
  isGuest: false,
  authProvider: 'google',
  needsOnboarding: true,
);

/// Lobby- and room-shaped stand-ins carrying the real targets' shapes, dressed
/// in the real host the way main.dart does it.
Widget _coachApp(String start) {
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(
        path: '/lobby',
        builder: (_, _) => Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  Text('What are we watching?', style: PTText.display),
                  const SizedBox(height: 24),
                  CoachTarget(
                    id: CoachTargetId.openRoom,
                    child: PTButton(label: 'Open a room', onPressed: () {}),
                  ),
                ],
              ),
            ),
          ),
        ),
        routes: [
          GoRoute(
            path: 'room/:id',
            builder: (_, _) => Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        spacing: 12,
                        children: [
                          Text("Maya's room", style: PTText.panelHeading),
                          CoachTarget(
                            id: CoachTargetId.roomCode,
                            child: Text('K7Q2ZP', style: PTText.mono),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: CoachTarget(
                          id: CoachTargetId.pickSource,
                          child: PTButton(label: 'Choose a video', expand: false, onPressed: () {}),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
  return MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: buildPTTheme(),
    routerConfig: router,
    builder: (context, child) => OnboardingCoachHost(router: router, child: child!),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    OnboardingCoach.instance = OnboardingCoach(testPrefs: await SharedPreferences.getInstance());
  });

  screenMatrix('onboarding/lobby-mark', (tester, c, s) async {
    await OnboardingCoach.instance.arm(lobbyMark: true, invited: false);
    await pumpAtSize(tester, _coachApp('/lobby'), c, textScale: s, wrapInApp: false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Open your first room'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('onboarding/room-mark', (tester, c, s) async {
    await OnboardingCoach.instance.arm(lobbyMark: false, invited: false);
    await pumpAtSize(tester, _coachApp('/lobby/room/r1'), c, textScale: s, wrapInApp: false);
    await tester.pump(OnboardingCoachHost.settle + const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("This is your room's code"), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('onboarding/name', (tester, c, s) async {
    await pumpDialogOpener(tester, c, s, (context) => showOnboarding(context, profile: _maya));
    expectShownWhole(tester, 'That\'s me');
    await finishCase(tester);
  });

  screenMatrix('onboarding/path', (tester, c, s) async {
    await pumpDialogOpener(tester, c, s, (context) => showOnboarding(context, profile: _maya));
    await tester.ensureVisible(find.text("That's me"));
    await tester.pump();
    await tester.tap(find.text("That's me"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('My partner, far away'), findsOneWidget);
    expectShownWhole(tester, 'Continue');
    await finishCase(tester);
  });

  screenMatrix('onboarding/invite', (tester, c, s) async {
    await pumpDialogOpener(
      tester,
      c,
      s,
      (context) => showOnboarding(context, profile: _maya, inviteCode: 'K7Q2ZP'),
    );
    expectShownWhole(tester, 'Take your seat');
    await finishCase(tester);
  });
}
