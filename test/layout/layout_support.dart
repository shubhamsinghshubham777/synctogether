import 'dart:io';

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/player/local_video_chooser.dart';
import 'package:synctogether/player/recent_videos.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/ui/glass.dart';

import '../support/screen_matrix.dart';

/// Asserts every on-screen Text matching [text] shows whole: no ellipsis and
/// no wrapped line (a one-word label that wraps broke mid-word).
void expectShownWhole(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsAtLeastNWidgets(1), reason: '"$text" missing');
  var checked = 0;
  for (final element in finder.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    // A FirstFit candidate that lost was never laid out at the real width.
    if (paragraph.debugNeedsLayout) continue;
    checked++;
    expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text" ellipsized');
    final lines = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    expect(
      lines.map((b) => b.top.round()).toSet().length,
      1,
      reason: '"$text" wrapped onto several lines',
    );
  }
  expect(checked, greaterThan(0), reason: '"$text" never laid out');
}

/// Asserts no overflow and - inside a [screenMatrix] case that has not opted
/// out - that every control respects the system insets, then unmounts so periodic timers (lobby polling,
/// loaders) are cancelled before the test ends.
/// No ordinary word may be squeezed into a box clearly narrower than itself.
///
/// A column that is too narrow does not overflow - the text engine just breaks
/// the word wherever it runs out of room, so a title became "Video faceca / ms",
/// a chat bubble ran one word per line and a label became a sliver, all with
/// every other layout check green. This reads every multi-line, non-ellipsized
/// plain paragraph on screen and fails when the box is more than 10% under its
/// longest word. Out of scope on purpose: long identifiers and names (test
/// strings are deliberately unbreakable), password dots, and the very largest
/// text sizes (over 1.5x), where a few points short on one long word is
/// ordinary typography.
void expectNoWordsBrokenMidWord(WidgetTester tester) {
  final offenders = <String>[];
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.attached && o.hasSize && o.size.width > 0) {
      final span = o.text;
      final plain = span is TextSpan && span.text != null && (span.children?.isEmpty ?? true);
      final multiline = o.maxLines == null || o.maxLines! > 1;
      if (plain &&
          multiline &&
          o.overflow != TextOverflow.ellipsis &&
          o.textScaler.scale(1) <= 1.5) {
        var longest = 0.0;
        var longestWord = '';
        for (final w in span.text!.split(RegExp(r'[\s\-/]+'))) {
          if (w.isEmpty || w.length > 14 || !RegExp(r'[A-Za-z0-9]').hasMatch(w)) continue;
          final tp = TextPainter(
            text: TextSpan(text: w, style: span.style),
            textDirection: TextDirection.ltr,
            textScaler: o.textScaler,
          )..layout();
          if (tp.width > longest) {
            longest = tp.width;
            longestWord = w;
          }
        }
        if (longest > 0 && o.size.width + 0.5 < longest * 0.9) {
          offenders.add(
            '"${span.text!.replaceAll('\n', ' ')}" is ${o.size.width.toStringAsFixed(0)} px wide '
            'but "$longestWord" needs ${longest.toStringAsFixed(0)}',
          );
        }
      }
    }
    o.visitChildren(visit);
  }

  for (final v in tester.binding.renderViews) {
    visit(v);
  }
  expect(
    offenders,
    isEmpty,
    reason: 'text squeezed so narrow that words break in the middle:\n${offenders.join('\n')}',
  );
}

Future<void> finishCase(WidgetTester tester) async {
  expectNoWordsBrokenMidWord(tester);
  await captureScreenshot(tester);
  expectNoOverflow(tester);
  expectSinglePaneClearOfHinge(tester);
  if (insetCheckActive) {
    await expectRespectsInsets(tester);
    expectNoOverflow(tester);
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
  // Anything thrown while tearing down is a bug too, but not a layout one.
  tester.takeException();
}

/// Pumps a button at [c], taps it to open [builder] through [showGlassDialog],
/// and lets the entrance transition finish (bounded - no pumpAndSettle).
Future<void> pumpGlassDialog(
  WidgetTester tester,
  ScreenCase c,
  double textScale,
  WidgetBuilder builder, {
  double width = 430,
}) {
  return pumpDialogOpener(
    tester,
    c,
    textScale,
    (context) => showGlassDialog<void>(context: context, width: width, builder: builder),
  );
}

/// Same as [pumpGlassDialog] for dialogs that own their `show*` entry point.
Future<void> pumpDialogOpener(
  WidgetTester tester,
  ScreenCase c,
  double textScale,
  void Function(BuildContext context) open,
) async {
  await pumpAtSize(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => Align(
          alignment: Alignment.topLeft,
          child: TextButton(onPressed: () => open(context), child: const Text('open')),
        ),
      ),
    ),
    c,
    textScale: textScale,
    checkHinge: true,
  );
  // The opener itself is not under test.
  tester.takeException();
  await tester.tap(find.text('open'), warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Rewards with no backend: loaded, a live streak, and a populated board.
class FakeRewardsService extends RewardsService {
  FakeRewardsService({this.fakeState = sampleRewardState, this.rows = sampleBoard});

  final RewardState fakeState;
  final List<LeaderboardRow> rows;

  @override
  RewardState get state => fakeState;

  @override
  bool get loaded => true;

  @override
  Future<RewardState?> load() async => fakeState;

  @override
  Future<List<LeaderboardRow>> leaderboard({
    LeaderboardScope scope = LeaderboardScope.circle,
    LeaderboardPeriod period = LeaderboardPeriod.week,
    int limit = 100,
  }) async => rows;

  @override
  Future<int> loadReferrals() async => 3;

  @override
  Future<List<SharedRecap>> loadSharedRecaps() async => const [];
}

const sampleRewardState = RewardState(
  publicProfile: true,
  streak: StreakState(current: 12, longest: 30, freezes: 2),
  weekRank: 3,
  circleRank: 2,
);

const sampleBoard = [
  LeaderboardRow(
    rank: 1,
    userId: 'u1',
    displayName: 'Maximiliana Featherstonehaugh-Wolfeschlegel',
    points: 123456,
    isPremium: true,
    streak: 41,
    seconds: 360000,
  ),
  LeaderboardRow(
    rank: 2,
    userId: 'user-alex',
    displayName: 'Alex Rivers',
    points: 9800,
    isMe: true,
    streak: 12,
  ),
  LeaderboardRow(rank: 3, userId: 'u3', displayName: 'Sam', points: 7200, streak: 3),
  LeaderboardRow(rank: 4, userId: 'u4', displayName: 'Priya Ramanathan', points: 4100),
  LeaderboardRow(rank: 5, userId: 'u5', displayName: 'Jo', points: 12),
];

Achievement _badge(
  String id,
  String title,
  String description,
  String metric,
  int threshold, {
  RewardGrade grade = RewardGrade.bronze,
  AvatarFrame? frame,
  DateTime? earnedAt,
}) => Achievement(
  id: id,
  title: title,
  description: description,
  icon: 'bolt',
  grade: grade,
  metric: metric,
  threshold: threshold,
  frame: frame,
  unlocked: earnedAt != null,
  unlockedAt: earnedAt,
);

/// The shipped catalogue (the `achievements` seed in the gamification
/// migration, descriptions verbatim) with four earned: what the leaderboard's
/// badge shelf and the badge catalog dialog render.
final sampleBadgesState = RewardState(
  publicProfile: true,
  streak: const StreakState(current: 12, longest: 12, freezes: 2),
  weekRank: 3,
  circleRank: 2,
  metrics: const {
    'longest_streak': 12,
    'max_room_members': 5,
    'longest_session_seconds': 6720,
    'distinct_co_watchers': 6,
    'total_seconds': 32700,
    'reactions_sent': 212,
    'total_hosted': 3,
    'messages_sent': 340,
    'days_active': 12,
  },
  achievements: [
    _badge(
      'first_sync',
      'First Sync',
      'Finish a session with someone else.',
      'total_sessions',
      1,
      earnedAt: DateTime(2026, 8, 12, 12),
    ),
    _badge(
      'week_one',
      'Regular',
      'Keep a 3-day watch streak.',
      'longest_streak',
      3,
      frame: AvatarFrame.ember,
      earnedAt: DateTime(2026, 8, 14, 12),
    ),
    _badge(
      'seven_up',
      'Seven Up',
      'Keep a 7-day watch streak.',
      'longest_streak',
      7,
      grade: RewardGrade.silver,
      earnedAt: DateTime(2026, 8, 22, 12),
    ),
    _badge(
      'unbroken',
      'Unbroken',
      'Keep a 30-day watch streak.',
      'longest_streak',
      30,
      grade: RewardGrade.gold,
      frame: AvatarFrame.aurora,
    ),
    _badge(
      'double_feature',
      'Double Feature',
      'Watch in two different rooms in one day.',
      'double_feature_days',
      1,
      earnedAt: DateTime(2026, 9, 3, 12),
    ),
    _badge(
      'full_house',
      'Full House',
      'Be in a room with 8 or more people.',
      'max_room_members',
      8,
      grade: RewardGrade.silver,
    ),
    _badge(
      'marathon',
      'Marathon',
      'Stay in one session for over 4 hours.',
      'longest_session_seconds',
      14400,
      grade: RewardGrade.silver,
    ),
    _badge('night_owl', 'Night Owl', 'Watch through 2am.', 'night_owl_sessions', 1),
    _badge(
      'wide_circle',
      'Wide Circle',
      'Watch with 10 different people.',
      'distinct_co_watchers',
      10,
      grade: RewardGrade.silver,
      frame: AvatarFrame.halo,
    ),
    _badge(
      'century',
      'Century',
      'Watch 100 hours together.',
      'total_seconds',
      360000,
      grade: RewardGrade.gold,
      frame: AvatarFrame.laurel,
    ),
    _badge('hype_man', 'Hype Machine', 'Send 500 reactions.', 'reactions_sent', 500),
    _badge(
      'host_with_most',
      'Host With The Most',
      'Host 25 sessions.',
      'total_hosted',
      25,
      grade: RewardGrade.silver,
    ),
    _badge('chatterbox', 'Chatterbox', 'Send 1,000 chat messages.', 'messages_sent', 1000),
    _badge(
      'devoted',
      'Devoted',
      'Be active on 100 different days.',
      'days_active',
      100,
      grade: RewardGrade.gold,
    ),
  ],
);

/// The board-47 shelf: four healthy rows (one with a very long name), one whose
/// file has moved, and the clock pinned so "Opened 2 hours ago" is stable.
/// [empty] leaves Recent with nothing in it. Files that should exist are created
/// under `build/chooser_media/` (outside any tmp/cache segment, which Recent
/// would refuse to remember).
Future<LocalVideoChooserServices> sampleChooserServices(
  ScreenCase c, {
  bool empty = false,
  FilePick? pickFile,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime(2026, 11, 6, 12);
  var clock = now;
  final recents = RecentVideos(
    prefs: prefs,
    thumbnailDir: () async => Directory('build/chooser_thumbs'),
    clock: () => clock,
  );
  final touch = c.platform == TargetPlatform.iOS || c.platform == TargetPlatform.android;
  if (!empty) {
    final samples = <(String, Duration, int, Duration, bool)>[
      (
        'Cosmic Voyage (2019).mkv',
        const Duration(hours: 2),
        9019860000,
        const Duration(hours: 2, minutes: 49, seconds: 3),
        true,
      ),
      ('IMG_4821.MOV', const Duration(hours: 20), 100663296, const Duration(seconds: 42), false),
      (
        'Nosferatu - Friday Horror Club - Extended Cut With Commentary (1922) 4K Remaster.mp4',
        const Duration(days: 3),
        1181116006,
        const Duration(hours: 1, minutes: 34, seconds: 10),
        true,
      ),
      (
        'holiday-reel-final.webm',
        const Duration(days: 8),
        325058560,
        const Duration(minutes: 12, seconds: 8),
        true,
      ),
      ('Wrong Turn.mp4', const Duration(days: 20), 734003200, const Duration(minutes: 96), true),
    ];
    for (final (name, ago, bytes, runtime, exists) in samples) {
      final path = exists
          ? (File('build/chooser_media/$name')..createSync(recursive: true)).absolute.path
          : '/moved/away/$name';
      clock = now.subtract(ago);
      await recents.record(
        LocalVideo(
          name: name,
          mediaUri: path,
          path: path,
          origin: VideoOrigin.files,
          reference: PathReference(path),
          sizeBytes: bytes,
        ),
        duration: runtime,
      );
    }
    clock = now;
  }
  return LocalVideoChooserServices(
    recents: recents,
    pickFile: pickFile ?? () async => null,
    pickPhoto: () async => null,
    showPhotos: touch,
    probeMissing: true,
    clock: () => now,
  );
}

/// A picker answer that is plainly not a video (the banner case).
Future<FastFilePickerPath?> pickNotAVideo() async =>
    FastFilePickerPath.fromPath('notes.pdf', '/docs/notes.pdf');

bool _editableFocused() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() !=
    null;

/// On a touch case, raises the keyboard on the first text field, then taps
/// around the screen (above the keyboard) until some tap closes it: proves that
/// *some* empty region of this layout answers a tap-away, whatever the
/// screen's shape. Taps are tried from the top-left, which is empty chrome
/// nearly everywhere, so the first or second usually does it. Desktop cases
/// are skipped - a click on empty space must not move focus there.
Future<void> expectTapAwayClosesKeyboard(WidgetTester tester, ScreenCase c, {Finder? field}) async {
  if (c.platform != TargetPlatform.iOS && c.platform != TargetPlatform.android) return;
  final target = field ?? find.byType(EditableText);
  expect(target, findsAtLeastNWidgets(1), reason: 'no text field on screen');
  Future<void> raise() async {
    await tester.showKeyboard(target.first);
    await tester.pump(const Duration(milliseconds: 400));
  }

  await raise();
  expect(_editableFocused(), isTrue, reason: 'precondition: the field has focus');
  final bottom = c.size.height - c.keyboard;
  var tries = 0;
  for (var y = 6.0; y < bottom; y += 44) {
    for (var x = 6.0; x < c.size.width; x += 44) {
      if (tries++ >= 60) fail('no tap on an empty region closed the keyboard');
      await tester.tapAt(Offset(x, y));
      await tester.pump(const Duration(milliseconds: 400));
      if (!_editableFocused()) return;
      if (target.evaluate().isEmpty) return; // the tap navigated away; focus went with it
      await raise();
    }
  }
  fail('no tap on an empty region closed the keyboard');
}
