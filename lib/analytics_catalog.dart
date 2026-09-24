/// Every product event this app can send, what it carries, and why.
///
/// This exists to be *shown to the user*, not to be read by developers: the
/// profile screen renders it verbatim behind "What we collect". A privacy
/// promise nobody can check is a promise nobody believes, and the fastest way
/// to make someone turn analytics off is to be vague about it.
///
/// `test/analytics_catalog_test.dart` fails the build if this list and the
/// `Analytics.track` calls in `lib/` ever disagree, in either direction - which
/// is what stops the dialog quietly becoming a lie.
library;

enum AnalyticsGroup {
  install('Getting started'),
  rooms('Rooms and watching'),
  engagement('Things you do in a room'),
  rewards('Streaks and badges'),
  safety('Safety and moderation'),
  premium('Premium');

  const AnalyticsGroup(this.title);

  final String title;
}

class AnalyticsEventDoc {
  const AnalyticsEventDoc({
    required this.event,
    required this.group,
    required this.what,
    required this.why,
    this.properties = const [],
  });

  /// The exact string passed to `Analytics.track`.
  final String event;
  final AnalyticsGroup group;

  /// What causes it, in the user's terms.
  final String what;

  /// Why it is worth collecting. If this cannot be written honestly, the event
  /// should not exist.
  final String why;

  /// Everything sent alongside it. Nothing here may ever be free text a person
  /// typed, a file name, a path, or a link.
  final List<String> properties;
}

/// What is *never* sent, stated positively so it can be shown next to the list.
const kAnalyticsNeverCollected = <String>[
  'Anything you type - chat messages are never read, counted per person, or sent',
  'What you watch - no file names, no folder paths, no YouTube links or video IDs',
  'Your video or audio - facecams are never recorded, stored or analysed',
  'Your contacts, your screen, your keystrokes or your location',
  'Any advertising or cross-app tracking identifier - there are no ad networks here',
];

const kAnalyticsEvents = <AnalyticsEventDoc>[
  // --- Getting started -----------------------------------------------------
  AnalyticsEventDoc(
    event: 'app_opened',
    group: .install,
    what: 'You launched SyncTogether.',
    why: 'Tells us how many people actually use the app, and whether they come back.',
    properties: ['platform (macOS or Windows)', 'app version'],
  ),
  AnalyticsEventDoc(
    event: 'signed_in',
    group: .install,
    what: 'You signed in.',
    why: 'Shows which sign-in methods are worth keeping and which are broken.',
    properties: ['method (Google, Apple, email or guest)'],
  ),
  AnalyticsEventDoc(
    event: 'guest_upgraded',
    group: .install,
    what: 'You turned a guest session into a real account.',
    why: 'The single clearest signal that the app was worth keeping.',
  ),

  // --- Rooms ---------------------------------------------------------------
  AnalyticsEventDoc(
    event: 'room_created',
    group: .rooms,
    what: 'You made a room.',
    why: 'How often rooms get made, and how long people set them up for.',
    properties: ['room ID', 'chosen duration', 'whether it is persistent'],
  ),
  AnalyticsEventDoc(
    event: 'room_joined',
    group: .rooms,
    what: 'You joined a room.',
    why: 'Tells us whether invites actually work - the link, or the typed code.',
    properties: ['room ID', 'how you joined (code, link or web page)'],
  ),
  AnalyticsEventDoc(
    event: 'room_join_failed',
    group: .rooms,
    what: 'Joining a room did not work.',
    why: 'A wrong code is fine. A spike in anything else is a bug we cannot see otherwise.',
    properties: ['the reason (room full, ended, banned, not found)'],
  ),
  AnalyticsEventDoc(
    event: 'room_extended',
    group: .rooms,
    what: 'You added time to a room.',
    why: 'Shows whether the default room length is too short.',
    properties: ['room ID', 'minutes added'],
  ),
  AnalyticsEventDoc(
    event: 'room_resumed',
    group: .rooms,
    what: 'You restarted a room from your lobby.',
    why: 'Tells us whether saved rooms are actually used or just clutter.',
    properties: ['room ID', 'duration'],
  ),
  AnalyticsEventDoc(
    event: 'room_deleted',
    group: .rooms,
    what: 'You deleted a room.',
    why: 'Paired with the above, shows whether the room limit is set sensibly.',
    properties: ['room ID'],
  ),
  AnalyticsEventDoc(
    event: 'limit_hit',
    group: .rooms,
    what: 'Something you tried was blocked by a plan limit.',
    why: 'The only way to know which limits are annoying rather than reasonable.',
    properties: ['which limit (room count, member cap, duration, upload quota)'],
  ),
  AnalyticsEventDoc(
    event: 'media_selected',
    group: .rooms,
    what: 'You picked something to watch.',
    why: 'Whether people use local files or YouTube. The kind only - never what it was.',
    properties: ['kind (local file or YouTube)', 'room ID'],
  ),
  AnalyticsEventDoc(
    event: 'playback_started',
    group: .rooms,
    what: 'Playback began in a room.',
    why: 'The point where a room becomes a watch party, which is the thing to get right.',
    properties: ['kind (local or YouTube)', 'how many people were present', 'room ID'],
  ),
  AnalyticsEventDoc(
    event: 'watch_session_ended',
    group: .rooms,
    what: 'You left a room.',
    why: 'How long sessions run and how big they get, so the limits can follow reality.',
    properties: [
      'minutes',
      'most people present at once',
      'counts of your own messages and reactions',
      'whether a facecam was on',
      'room ID',
    ],
  ),
  AnalyticsEventDoc(
    event: 'gate_override_used',
    group: .rooms,
    what: 'A host started without waiting for everyone.',
    why: 'Tells us how often the readiness gate gets in the way rather than helping.',
    properties: ['how many people were skipped', 'room ID'],
  ),
  AnalyticsEventDoc(
    event: 'invite_copied',
    group: .rooms,
    what: 'You copied an invite link.',
    why: 'How people actually invite others, and whether those invites convert.',
    properties: ['room ID'],
  ),

  // --- In a room -----------------------------------------------------------
  AnalyticsEventDoc(
    event: 'chat_message_sent',
    group: .engagement,
    what: 'You sent a chat message.',
    why: 'A count, so we know chat is used. The message itself is never sent anywhere.',
    properties: ['room ID'],
  ),
  AnalyticsEventDoc(
    event: 'reaction_sent',
    group: .engagement,
    what: 'You sent a reaction.',
    why: 'Which emoji earn their place in the strip, and which nobody ever taps.',
    properties: ['which emoji', 'room ID'],
  ),
  AnalyticsEventDoc(
    event: 'facecam_toggled',
    group: .engagement,
    what: 'You turned your mic or camera on or off.',
    why: 'Whether facecams are used at all. No audio or video is involved.',
    properties: ['mic or camera', 'on or off'],
  ),

  // --- Streaks and badges --------------------------------------------------
  AnalyticsEventDoc(
    event: 'achievement_unlocked',
    group: .rewards,
    what: 'You earned a badge.',
    why: 'Which badges are reachable and which are effectively impossible.',
    properties: ['badge ID', 'its tier (bronze, silver, gold)'],
  ),
  AnalyticsEventDoc(
    event: 'recap_shown',
    group: .rewards,
    what: 'A session recap was offered when you left a room.',
    why: 'Paired with the next one, tells us whether recaps are worth offering.',
    properties: ['room ID', 'session length', 'people present'],
  ),
  AnalyticsEventDoc(
    event: 'recap_shared',
    group: .rewards,
    what: 'You shared a recap.',
    why: 'The single most useful number we have: whether anyone wants to show this off.',
    properties: ['where you shared it from'],
  ),
  AnalyticsEventDoc(
    event: 'leaderboard_viewed',
    group: .rewards,
    what: 'You opened a leaderboard.',
    why: 'Which board people actually look at - their circle, or everyone.',
    properties: ['which board'],
  ),
  AnalyticsEventDoc(
    event: 'leaderboard_opt_in',
    group: .rewards,
    what: 'You turned public leaderboards on or off.',
    why: 'Whether the opt-in is understood, or whether people turn it straight back off.',
    properties: ['on or off'],
  ),
  AnalyticsEventDoc(
    event: 'frame_equipped',
    group: .rewards,
    what: 'You changed your avatar frame.',
    why: 'Whether cosmetic rewards are worth making more of.',
    properties: ['which frame'],
  ),
  AnalyticsEventDoc(
    event: 'recap_deleted',
    group: .rewards,
    what: 'You took a shared recap back down.',
    why:
        'A share that gets deleted is not a share - this is what keeps the '
        'previous number honest.',
    properties: ['how many times it had been opened'],
  ),
  AnalyticsEventDoc(
    event: 'profile_shared',
    group: .rewards,
    what: 'You shared your public profile link.',
    why: 'Whether profile pages bring anybody new in.',
    properties: ['where you shared it from'],
  ),
  AnalyticsEventDoc(
    event: 'handle_claimed',
    group: .rewards,
    what: 'You claimed your public handle.',
    why:
        'Whether the one thing Premium adds here is worth having. The handle '
        'itself is not sent.',
  ),

  // --- Safety and moderation -----------------------------------------------
  AnalyticsEventDoc(
    event: 'content_reported',
    group: .safety,
    what: 'You reported someone in a room.',
    why:
        'So we can tell whether the report button is findable, and how often '
        'it is needed. Only the category you picked is sent here - anything '
        'you typed goes to the moderation queue, never to analytics.',
    properties: ['the category you picked'],
  ),
  AnalyticsEventDoc(
    event: 'user_blocked',
    group: .safety,
    what: 'You blocked someone.',
    why: 'Whether blocking is reachable at the moment people need it.',
    properties: ['the category it was filed under'],
  ),
  AnalyticsEventDoc(
    event: 'user_unblocked',
    group: .safety,
    what: 'You unblocked someone.',
    why: 'Whether blocks are being used as a mute and then undone.',
  ),

  // --- Premium -------------------------------------------------------------
  AnalyticsEventDoc(
    event: 'upgrade_cta_shown',
    group: .premium,
    what: 'You were shown a Premium prompt.',
    why: 'So we can tell a useful prompt from a nag, and remove the nags.',
    properties: ['where it appeared'],
  ),
  AnalyticsEventDoc(
    event: 'upgrade_cta_clicked',
    group: .premium,
    what: 'You tapped a Premium prompt.',
    why: 'Same reason, from the other side.',
    properties: ['where it appeared', 'what it offered (sign in, or keep me posted)'],
  ),
  AnalyticsEventDoc(
    event: 'subscription_screen_viewed',
    group: .premium,
    what: 'You opened the Premium screen.',
    why: 'Where people come to it from.',
    properties: ['where you came from'],
  ),
  AnalyticsEventDoc(
    event: 'checkout_opened',
    group: .premium,
    what: 'You opened checkout in your browser.',
    why: 'Whether the hand-off to the browser loses people.',
    properties: ['where you came from'],
  ),
  AnalyticsEventDoc(
    event: 'app_store_purchase_started',
    group: .premium,
    what: 'You started an App Store purchase of Premium.',
    why: 'Whether the App Store sheet loses people.',
    properties: ['where you came from', 'monthly or annual'],
  ),
  AnalyticsEventDoc(
    event: 'purchase_confirmed',
    group: .premium,
    what: 'A Premium subscription became active on your account.',
    why:
        'Confirms the purchase reached the app. No payment details are ever involved -'
        ' card details never touch SyncTogether at all.',
  ),
];

/// Grouped for rendering, preserving declaration order inside each group.
Map<AnalyticsGroup, List<AnalyticsEventDoc>> analyticsEventsByGroup() {
  final out = <AnalyticsGroup, List<AnalyticsEventDoc>>{};
  for (final doc in kAnalyticsEvents) {
    (out[doc.group] ??= <AnalyticsEventDoc>[]).add(doc);
  }
  return out;
}
