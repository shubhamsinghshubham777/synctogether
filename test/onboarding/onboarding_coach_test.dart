import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/onboarding/onboarding_coach.dart';
import 'package:synctogether/ui/coach_target.dart';
import 'package:synctogether/ui/pt_theme.dart';

int opened = 0;

GoRouter _router(String start) => GoRouter(
  initialLocation: start,
  routes: [
    GoRoute(
      path: '/lobby',
      builder: (_, _) => Scaffold(
        body: Center(
          child: CoachTarget(
            id: CoachTargetId.openRoom,
            onActivate: () => opened++,
            child: FilledButton(onPressed: () {}, child: const Text('Open a room')),
          ),
        ),
      ),
      routes: [
        GoRoute(
          path: 'room/:id',
          builder: (_, _) => Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 40),
                CoachTarget(
                  id: CoachTargetId.roomCode,
                  child: TextButton(onPressed: () {}, child: const Text('K7Q2ZP')),
                ),
                const Spacer(),
                CoachTarget(
                  id: CoachTargetId.pickSource,
                  child: FilledButton(onPressed: () {}, child: const Text('Choose a video')),
                ),
                const Spacer(),
                CoachTarget(
                  id: CoachTargetId.play,
                  child: IconButton(onPressed: () {}, icon: const Icon(Icons.play_arrow)),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    ),
  ],
);

Future<void> _pump(WidgetTester tester, String start) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = _router(start);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: buildPTTheme(),
      routerConfig: router,
      builder: (context, child) => OnboardingCoachHost(router: router, child: child!),
    ),
  );
  await tester.pump(OnboardingCoachHost.settle + const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    opened = 0;
    SharedPreferences.setMockInitialValues({});
    OnboardingCoach.instance = OnboardingCoach(testPrefs: await SharedPreferences.getInstance());
  });

  testWidgets('nothing armed, nothing shown', (tester) async {
    await _pump(tester, '/lobby');
    expect(find.text('Open your first room'), findsNothing);
  });

  testWidgets('the lobby mark runs the button\'s own action and is never shown again', (
    tester,
  ) async {
    await OnboardingCoach.instance.arm(lobbyMark: true, invited: false);
    await _pump(tester, '/lobby');
    expect(find.text('Open your first room'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Open a room').last);
    await tester.pumpAndSettle();
    expect(opened, 0, reason: 'the tap went to the lit button itself, not the card');
    expect(find.text('Open your first room'), findsNothing);
    expect(OnboardingCoach.instance.lobbyMarkPending, isFalse);
  });

  testWidgets('"Open a room" on the card activates the target', (tester) async {
    await OnboardingCoach.instance.arm(lobbyMark: true, invited: false);
    await _pump(tester, '/lobby');
    await tester.tap(find.text('Open a room').last);
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('room marks walk with Next and clear when done', (tester) async {
    await OnboardingCoach.instance.arm(lobbyMark: false, invited: false);
    await _pump(tester, '/lobby/room/r1');
    expect(find.text('Pick what to watch'), findsOneWidget);
    expect(find.text("1 OF 3 · WHAT'S ON"), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("This is your room's code"), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Everyone holds the remote'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Everyone holds the remote'), findsNothing);
    expect(OnboardingCoach.instance.roomMarksInvited, isNull);
  });

  testWidgets('an invitee is not told to share the code', (tester) async {
    await OnboardingCoach.instance.arm(lobbyMark: false, invited: true);
    await _pump(tester, '/lobby/room/r1');
    expect(find.text("1 OF 2 · WHAT'S ON"), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Everyone holds the remote'), findsOneWidget);
  });

  testWidgets('a tap on the dim ends the whole set', (tester) async {
    await OnboardingCoach.instance.arm(lobbyMark: false, invited: false);
    await _pump(tester, '/lobby/room/r1');
    await tester.tapAt(const Offset(1100, 250));
    await tester.pumpAndSettle();
    expect(find.text("This is your room's code"), findsNothing);
    expect(OnboardingCoach.instance.roomMarksInvited, isNull);
  });
}
