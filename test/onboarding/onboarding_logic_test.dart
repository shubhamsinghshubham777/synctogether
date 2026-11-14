import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/onboarding/onboarding_logic.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/ui/coach_target.dart';

void main() {
  test('an invite skips the path question', () {
    expect(onboardingSteps(invited: false), [OnboardingStep.name, OnboardingStep.path]);
    expect(onboardingSteps(invited: true), [OnboardingStep.name]);
  });

  test('guests are never offered pairing', () {
    expect(pathOptions(isGuest: true), isNot(contains(OnboardingPath.partner)));
    expect(pathOptions(isGuest: false), contains(OnboardingPath.partner));
  });

  test('names: empty and over-long are refused with friendly copy', () {
    expect(nameError('   '), isNotNull);
    expect(nameError('x' * 41), contains('40'));
    expect(nameError(' Maya '), isNull);
    expect(nameError('x' * 40), isNull);
  });

  test('a server-made guest name starts the field empty; real names stay', () {
    expect(initialName('Guest-a1b2'), '');
    expect(initialName('Guest-Night'), 'Guest-Night');
    expect(initialName('shubham777'), 'shubham777');
  });

  test('the name note names where the name came from', () {
    expect(nameNote('google'), contains('Google'));
    expect(nameNote('apple'), contains('Apple'));
    expect(nameNote('email'), isNot(contains('Filled in')));
    expect(
      nameNote('apple', displayName: 'x7k2q9', email: 'x7k2q9@privaterelay.appleid.com'),
      isNot(contains('Apple')),
    );
    expect(
      nameNote('google', displayName: 'Maya Lin', email: 'maya@example.com'),
      contains('Google'),
    );
  });

  test('analytics path: invite wins, a missing path reads as browsing', () {
    expect(finishedAnalyticsPath(OnboardingPath.friends, invited: true), 'invite');
    expect(finishedAnalyticsPath(OnboardingPath.partner, invited: false), 'partner');
    expect(finishedAnalyticsPath(null, invited: false), 'browsing');
  });

  test('room marks: invitees are not told to share the code', () {
    expect(roomMarks(invited: true), isNot(contains(CoachTargetId.roomCode)));
    expect(roomMarks(invited: false).first, CoachTargetId.pickSource);
  });

  test('marks whose control is off screen are dropped and the rest renumbered', () {
    final shown = visibleRoomMarks(
      roomMarks(invited: false),
      (id) => id != CoachTargetId.pickSource,
    );
    expect(shown, [CoachTargetId.roomCode, CoachTargetId.play]);
    expect(roomMarkCopy(shown.first, 1, shown.length).kicker, startsWith('1 OF 2'));
  });

  group('Profile.needsOnboarding', () {
    Map<String, dynamic> row([Map<String, dynamic> extra = const {}]) => {
      'id': 'u1',
      'display_name': 'Maya',
      'is_guest': false,
      ...extra,
    };

    test('true only when the column is present and null', () {
      expect(Profile.fromJson(row({'onboarded_at': null})).needsOnboarding, isTrue);
      expect(
        Profile.fromJson(row({'onboarded_at': '2026-11-14T10:00:00Z'})).needsOnboarding,
        isFalse,
      );
    });

    test('an older backend without the column never triggers it', () {
      expect(Profile.fromJson(row()).needsOnboarding, isFalse);
    });

    test('defaults to false, and copyWith can clear it', () {
      const p = Profile(id: 'u1', displayName: 'M', isGuest: false, needsOnboarding: true);
      expect(const Profile(id: 'u1', displayName: 'M', isGuest: false).needsOnboarding, isFalse);
      expect(p.copyWith(needsOnboarding: false).needsOnboarding, isFalse);
      expect(p.copyWith(displayName: 'N').needsOnboarding, isTrue);
    });
  });
}
