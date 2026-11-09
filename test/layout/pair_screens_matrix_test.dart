import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/date_night_plan.dart';
import 'package:synctogether/pairing/pair_page.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/pairing/date_night_screen.dart';
import 'package:synctogether/pairing/history_screen.dart';
import 'package:synctogether/pairing/notification_settings_screen.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/pairing/push_service.dart';
import 'package:synctogether/pairing/year_recap_screen.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/rewards/rewards_service.dart';
import 'package:synctogether/ui/pt_theme.dart';

import '../support/fake_pair_service.dart';
import '../support/screen_matrix.dart';
import 'layout_support.dart';

class _Bridge implements PushBridge {
  _Bridge(this.state);
  PushPermission state;

  @override
  Future<void> configure(Map<String, String>? firebase) async {}
  @override
  Future<PushPermission> permission() async => state;
  @override
  Future<PushPermission> request() async => state;
  @override
  Future<PushToken?> token() async => null;
  @override
  Stream<PushToken> get tokenChanges => const Stream.empty();
  @override
  Stream<String?> get taps => const Stream.empty();
  @override
  Future<String?> launchRoute() async => null;
  @override
  Future<void> openSettings() async {}
}

DateNight _night(String id, DateNightStatus status, Duration from, {String by = 'sam'}) =>
    DateNight(
      id: id,
      title: 'Spirited Away',
      startsAt: DateTime.now().toUtc().add(from),
      proposedBy: by,
      status: status,
    );

DateNight _fileNight(
  String id, {
  required String state,
  int bytes = 0,
  Duration startsIn = const Duration(days: 3),
  String by = 'user-alex',
  DateNightStatus status = DateNightStatus.accepted,
}) => DateNight(
  id: id,
  title: 'Spirited Away',
  startsAt: DateTime.now().toUtc().add(startsIn),
  proposedBy: by,
  status: status,
  attachKind: 'file',
  fileName: 'spirited_away_1080p.mkv',
  fileSize: 1000,
  uploadState: state,
  uploadBytes: bytes,
);

/// The plan form with a file already chosen, as a page, so the file panel's
/// states can be laid out at every size without a platform file chooser.
Widget _planFormWithFile(int bytes) {
  final form = PlanNightController(PairService.instance.pair!)
    ..video = LocalVideo(
      name: 'spirited_away_1080p.mkv',
      mediaUri: '/m/spirited_away_1080p.mkv',
      path: '/m/spirited_away_1080p.mkv',
      origin: VideoOrigin.files,
      reference: const PathReference('/m/spirited_away_1080p.mkv'),
      sizeBytes: bytes,
    )
    ..fileSize = bytes
    ..attach = PlanAttach.file;
  return PairPage(
    title: 'Plan a date night',
    children: [PlanNightBody(form: form)],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
    RewardsService.instance = FakeRewardsService();
  });

  screenMatrix('pair/nights', (tester, c, s) async {
    PairService.instance = FakePairService(
      pair: samePairInfo(patron: true),
      nights: [
        _night('a', DateNightStatus.accepted, const Duration(minutes: 12)),
        _night('b', DateNightStatus.proposed, const Duration(days: 3)),
        _night('c', DateNightStatus.proposed, const Duration(days: 5), by: 'user-alex'),
        _night('d', DateNightStatus.accepted, const Duration(days: 9)),
      ],
    );
    await pumpAtSize(tester, const DateNightScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("I'm in"), findsOneWidget, reason: 'only the one proposed by Sam awaits me');
    expect(find.text('COMING UP · 4'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget, reason: 'with a list, Plan moves into the header');
    expect(find.text('Plan a date night'), findsNothing);
    await finishCase(tester);
  });

  for (final c in <({String name, DateNight night, List<String> expect, List<String> absent})>[
    (
      name: 'uploading',
      night: _fileNight('f1', state: 'uploading', bytes: 620),
      expect: ['UPLOADING 62%', 'Keep SyncTogether open until it says Ready.'],
      absent: ['Try again'],
    ),
    (
      name: 'ready',
      night: _fileNight('f2', state: 'ready', bytes: 1000),
      expect: ['READY', 'The movie is waiting. Sam can already stream it.'],
      absent: ['Try again'],
    ),
    (
      name: 'unfinished',
      night: _fileNight(
        'f3',
        state: 'uploading',
        bytes: 840,
        startsIn: const Duration(minutes: 10),
      ),
      expect: ['STILL UPLOADING 84%', 'The room still opens.'],
      absent: ['Try again'],
    ),
    (
      name: 'stopped',
      night: _fileNight('f4', state: 'stopped', bytes: 380),
      expect: ['UPLOAD STOPPED', 'Try again', 'Choose together'],
      absent: [],
    ),
  ]) {
    screenMatrix('pair/nights-file-${c.name}', (tester, cs, s) async {
      PairService.instance = FakePairService(pair: samePairInfo(patron: true), nights: [c.night]);
      await pumpAtSize(tester, const DateNightScreen(), cs, textScale: s, singlePane: true);
      await tester.pump(const Duration(milliseconds: 500));
      for (final text in c.expect) {
        await tester.ensureVisible(find.textContaining(text).first);
        expect(find.textContaining(text), findsWidgets, reason: text);
      }
      for (final text in c.absent) {
        expect(find.text(text), findsNothing, reason: text);
      }
      await finishCase(tester);
    });
  }

  screenMatrix('pair/nights-file-partner-view', (tester, cs, s) async {
    PairService.instance = FakePairService(
      pair: samePairInfo(patron: true),
      nights: [_fileNight('f5', state: 'uploading', bytes: 620, by: 'sam')],
    );
    await pumpAtSize(tester, const DateNightScreen(), cs, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.textContaining('is still uploading it'));
    expect(find.textContaining('Sam is still uploading it.'), findsOneWidget);
    expect(
      find.textContaining('Keep SyncTogether open'),
      findsNothing,
      reason: 'that is the planner\'s to do, not theirs',
    );
    expect(find.text('Try again'), findsNothing);
    await finishCase(tester);
  });

  screenMatrix('pair/nights-empty', (tester, c, s) async {
    // No known zone for them is the "same clock" case: one time, shown once.
    PairService.instance = FakePairService(pair: samePairInfo(patron: true, partnerZone: null));
    await pumpAtSize(tester, const DateNightScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('NOTHING PLANNED'), findsOneWidget);
    expect(find.text('Pick a night. Pick a movie.'), findsOneWidget);
    await tester.ensureVisible(find.text('Plan a date night'));
    expect(find.text('Plan a date night'), findsOneWidget, reason: 'the one amber button');
    expect(
      find.textContaining('The time is shown once'),
      findsOneWidget,
      reason: 'same zone, so the clocks are not promised twice',
    );
    await finishCase(tester);
  });

  testWidgets('with two different clocks the first step promises both', (tester) async {
    PairService.instance = FakePairService(pair: samePairInfo(patron: true));
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildPTTheme(), home: const DateNightScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Both clocks are shown.'), findsOneWidget);
    expect(find.textContaining('The time is shown once'), findsNothing);
  });

  screenMatrix('pair/nights-empty-free', (tester, c, s) async {
    canSellPremiumOverride = true;
    addTearDown(() => canSellPremiumOverride = null);
    PairService.instance = FakePairService(pair: samePairInfo());
    await pumpAtSize(tester, const DateNightScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Date nights come with a Patron seat.'), findsOneWidget);
    await tester.ensureVisible(find.text('See Patron'));
    expect(find.text('See Patron'), findsOneWidget);
    expect(find.textContaining('Answering never needs Patron'), findsOneWidget);
    expect(find.text('Plan a date night'), findsNothing, reason: 'absent, not disabled');
    await finishCase(tester);
  });

  screenMatrix('pair/nights-loading', (tester, c, s) async {
    PairService.instance = FakePairService(
      pair: samePairInfo(patron: true),
      nightsAreLoaded: false,
    );
    await pumpAtSize(tester, const DateNightScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('COMING UP'), findsOneWidget);
    expect(
      find.text('Pick a night. Pick a movie.'),
      findsNothing,
      reason: 'not yet an empty state',
    );
    expect(find.text("Couldn't load your date nights just now."), findsNothing);
    await finishCase(tester);
  });

  screenMatrix('pair/nights-error', (tester, c, s) async {
    final fake = FakePairService(
      pair: samePairInfo(patron: true),
      nightsAreLoaded: true,
      nightsDidFail: true,
    );
    PairService.instance = fake;
    await pumpAtSize(tester, const DateNightScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Couldn't load your date nights just now."), findsOneWidget);
    expect(find.textContaining("Nights you've already planned are safe"), findsOneWidget);
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.calls, contains('retryNights'));
    await finishCase(tester);
  });

  screenMatrix('pair/nights-free-booked', (tester, c, s) async {
    canSellPremiumOverride = true;
    addTearDown(() => canSellPremiumOverride = null);
    PairService.instance = FakePairService(
      pair: samePairInfo(),
      nights: [_night('a', DateNightStatus.accepted, const Duration(days: 6))],
    );
    await pumpAtSize(tester, const DateNightScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('See Patron'));
    expect(find.textContaining('Booked nights keep running'), findsOneWidget);
    expect(find.text('Plan'), findsNothing, reason: 'planning another needs Patron');
    await finishCase(tester);
  });

  for (final c in <({String name, int bytes, String expect})>[
    (
      name: 'fits',
      bytes: (1.8 * 1024 * 1024 * 1024).round(),
      expect: "This week's upload allowance",
    ),
    (name: 'over-cap', bytes: 3 * 1024 * 1024 * 1024, expect: 'a free seat can share'),
  ]) {
    screenMatrix('pair/plan-night-file-${c.name}', (tester, cs, s) async {
      PairService.instance = FakePairService(pair: samePairInfo(patron: true, partnerZone: null));
      await pumpAtSize(tester, _planFormWithFile(c.bytes), cs, textScale: s, singlePane: true);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.textContaining(c.expect).first);
      expect(find.textContaining(c.expect), findsWidgets);
      await finishCase(tester);
    });
  }

  screenMatrix('pair/plan-night', (tester, c, s) async {
    PairService.instance = FakePairService(pair: samePairInfo(patron: true));
    await pumpAtSize(tester, const PlanNightScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Send to Sam'), findsOneWidget);
    expect(find.text('BOTH OF YOU, SIDE BY SIDE'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/plan-night-same-zone', (tester, c, s) async {
    PairService.instance = FakePairService(pair: samePairInfo(patron: true, partnerZone: null));
    await pumpAtSize(tester, const PlanNightScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Send to Sam'), findsOneWidget);
    expect(find.text('BOTH OF YOU, SIDE BY SIDE'), findsNothing);
    await finishCase(tester);
  });

  screenMatrix('pair/history', (tester, c, s) async {
    final now = DateTime.now().toUtc();
    PairService.instance = FakePairService(
      pair: samePairInfo(),
      stats: const PairStats(
        streakWeeks: 12,
        bestStreakWeeks: 12,
        nights: 47,
        hours: 112.4,
        films: 31,
        doneThisWeek: true,
      ),
      history: PairHistory(
        lockedCount: 45,
        items: [
          PairSession(
            title: 'Spirited Away',
            startedAt: now.subtract(const Duration(days: 1)),
            seconds: 7500,
          ),
          PairSession(
            title: 'Perfect Days',
            startedAt: now.subtract(const Duration(days: 4)),
            seconds: 7440,
          ),
          PairSession(title: null, startedAt: now.subtract(const Duration(days: 6)), seconds: 2400),
        ],
      ),
    );
    await pumpAtSize(tester, const HistoryScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('45 older nights are kept safe'), findsOneWidget);
    expect(find.text('Export my history'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/year', (tester, c, s) async {
    PairService.instance = FakePairService(
      pair: samePairInfo(),
      stats: const PairStats(
        streakWeeks: 12,
        bestStreakWeeks: 12,
        nights: 47,
        hours: 112.4,
        films: 31,
      ),
    );
    await pumpAtSize(tester, const YearRecapScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Share image'), findsOneWidget);
    expect(find.textContaining('hours watching the same screen'), findsOneWidget);
    await finishCase(tester);
  });

  for (final (name, state) in [
    ('granted', PushPermission.granted),
    ('denied', PushPermission.denied),
    ('unsupported', PushPermission.unsupported),
  ]) {
    screenMatrix('pair/notifications-$name', (tester, c, s) async {
      PairService.instance = FakePairService(pair: samePairInfo());
      PushService.instance = PushService(
        bridge: _Bridge(state),
        register: (_) async {},
        unregister: (_) async {},
      );
      await pumpAtSize(
        tester,
        const NotificationSettingsScreen(),
        c,
        textScale: s,
        singlePane: true,
      );
      await tester.pump(const Duration(milliseconds: 500));
      if (state == PushPermission.unsupported) {
        expect(find.text('Quiet hours'), findsNothing, reason: 'no switches that cannot work');
      } else {
        expect(find.text('Quiet hours'), findsOneWidget);
      }
      if (state == PushPermission.denied) expect(find.text('Open settings'), findsOneWidget);
      await finishCase(tester);
    });
  }
}
