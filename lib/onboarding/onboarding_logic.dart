import '../ui/coach_target.dart';

/// Pure decisions behind the first-night flow, over plain values, so they are
/// testable without widgets, prefs or a backend (same seam as `sync_logic.dart`).

/// Who the user said they are watching with. Decides where they land.
enum OnboardingPath { friends, partner, browsing }

enum OnboardingStep { name, path }

/// The longest display name the server accepts (`complete_onboarding`).
const kMaxDisplayName = 40;

/// Arriving from an invite skips the path question: someone is already waiting.
List<OnboardingStep> onboardingSteps({required bool invited}) =>
    invited ? const [.name] : const [.name, .path];

/// Pairing needs a real account, so guests never see the partner option.
List<OnboardingPath> pathOptions({required bool isGuest}) =>
    isGuest ? const [.friends, .browsing] : const [.friends, .partner, .browsing];

/// Friendly copy for a name that cannot be saved, or null when it can.
String? nameError(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return "Your ticket needs a name.";
  if (name.length > kMaxDisplayName) return 'Keep it under $kMaxDisplayName characters.';
  return null;
}

/// The line under the name field, naming where the prefilled name came from -
/// but only when it really came from the provider. A name that is just the
/// email's local part (what the server falls back to, and all an Apple private
/// relay address yields) was never "filled in" from anywhere.
String nameNote(String? authProvider, {String? displayName, String? email}) {
  final local = email?.split('@').first.toLowerCase();
  final fromEmail = local != null && displayName?.trim().toLowerCase() == local;
  if (fromEmail) return 'We used your email for now. Change it any time in Profile.';
  return switch (authProvider) {
    'google' => 'Filled in from Google. Change it any time in Profile.',
    'apple' => 'Filled in from your Apple ID. Change it any time in Profile.',
    _ => 'You can change it any time in Profile.',
  };
}

/// The server names a guest `Guest-xxxx`; offering that back as "your name"
/// reads as a placeholder, so the field starts empty for them.
String initialName(String displayName) =>
    RegExp(r'^Guest-[0-9a-f]{4}$').hasMatch(displayName) ? '' : displayName;

String pathTitle(OnboardingPath p) => switch (p) {
  .friends => 'A group of friends',
  .partner => 'My partner, far away',
  .browsing => 'Just looking around',
};

String pathBody(OnboardingPath p) => switch (p) {
  .friends => 'Open a room and share its 6-letter code.',
  .partner => 'Pair up for a private room that never closes, plus date nights across time zones.',
  .browsing => 'Straight to the lobby. No tour.',
};

/// The analytics value of a finished flow. An invite has no path question.
String finishedAnalyticsPath(OnboardingPath? p, {required bool invited}) =>
    invited ? 'invite' : (p ?? OnboardingPath.browsing).name;

/// The room marks in the order they play. An invitee is not the one sharing
/// the code, so theirs leave that mark out. Marks whose control is not on
/// screen are dropped by the caller (see [visibleRoomMarks]).
List<CoachTargetId> roomMarks({required bool invited}) =>
    invited ? const [.pickSource, .play] : const [.pickSource, .roomCode, .play];

/// The marks that can actually be shown: only ones whose control is mounted.
List<CoachTargetId> visibleRoomMarks(List<CoachTargetId> marks, bool Function(CoachTargetId) on) =>
    [
      for (final m in marks)
        if (on(m)) m,
    ];

/// Card copy for one room mark, numbered against how many will really show.
({String kicker, String title, String body}) roomMarkCopy(CoachTargetId id, int step, int steps) {
  final n = '$step OF $steps';
  return switch (id) {
    .pickSource => (
      kicker: "$n · WHAT'S ON",
      title: 'Pick what to watch',
      body: 'A video file or a YouTube link. Everyone plays the same one, in sync.',
    ),
    .roomCode => (
      kicker: '$n · BRING FRIENDS IN',
      title: "This is your room's code",
      body:
          'Tap it to copy an invite link. Friends open it, or type the six letters under Enter a code.',
    ),
    .play => (
      kicker: '$n · ONE REMOTE',
      title: 'Everyone holds the remote',
      body: 'Play, pause or skip from any seat and the whole room follows.',
    ),
    .openRoom => (
      kicker: 'START HERE',
      title: 'Open your first room',
      body: "It's ready in a second. You'll get a code to send your friends once you're inside.",
    ),
  };
}
