import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/pairing/date_night_screen.dart';
import 'package:synctogether/pairing/history_screen.dart';
import 'package:synctogether/pairing/notification_settings_screen.dart';
import 'package:synctogether/pairing/pair_models.dart';
import 'package:synctogether/pairing/pair_service.dart';
import 'package:synctogether/pairing/pick_tonight_screen.dart';
import 'package:synctogether/pairing/push_service.dart';
import 'package:synctogether/pairing/watchlist_screen.dart';
import 'package:synctogether/pairing/year_recap_screen.dart';
import 'package:synctogether/rewards/rewards_service.dart';

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

WatchlistItem _item(
  String id,
  String title, {
  bool mine = false,
  bool file = true,
  bool watched = false,
}) => WatchlistItem(
  id: id,
  title: title,
  source: file ? WatchSource.local : WatchSource.youtube,
  sourceUrl: file ? null : 'https://youtu.be/x',
  addedBy: mine ? 'user-alex' : 'sam',
  createdAt: DateTime.utc(2026, 11, 1),
  watched: watched,
);

final _items = [
  _item('1', 'Past Lives', file: false),
  _item('2', 'Perfect Days', mine: true),
  _item('3', 'Spirited Away', mine: true),
  _item('4', 'Aftersun', file: false),
  _item('5', 'The Worst Person in the World an extraordinarily long title that must wrap'),
  _item('6', 'Drive My Car', watched: true),
];

DateNight _night(String id, DateNightStatus status, Duration from, {String by = 'sam'}) =>
    DateNight(
      id: id,
      title: 'Spirited Away',
      startsAt: DateTime.now().toUtc().add(from),
      proposedBy: by,
      status: status,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockDependencies();
    RewardsService.instance = FakeRewardsService();
  });

  screenMatrix('pair/watchlist', (tester, c, s) async {
    PairService.instance = FakePairService(pair: samePairInfo(), watchlist: _items);
    await pumpAtSize(tester, const WatchlistScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pick tonight'), findsOneWidget);
    expect(find.textContaining('NEEDS THE SAME FILE'), findsWidgets);
    await finishCase(tester);
  });

  screenMatrix('pair/watchlist-empty', (tester, c, s) async {
    PairService.instance = FakePairService(pair: samePairInfo());
    await pumpAtSize(tester, const WatchlistScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Nothing on the list yet'), findsOneWidget);
    expect(find.text('Pick tonight'), findsNothing, reason: 'nothing to pick from');
    await finishCase(tester);
  });

  screenMatrix('pair/pick', (tester, c, s) async {
    PairService.instance = FakePairService(pair: samePairInfo(), watchlist: _items, online: true);
    await pumpAtSize(tester, const PickTonightScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('1 of 5'.toUpperCase()), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    await finishCase(tester);
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
    expect(find.text('Plan a date night'), findsOneWidget);
    await finishCase(tester);
  });

  screenMatrix('pair/nights-empty-free', (tester, c, s) async {
    PairService.instance = FakePairService(pair: samePairInfo());
    await pumpAtSize(tester, const DateNightScreen(), c, textScale: s, singlePane: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Nothing planned'), findsOneWidget);
    expect(find.textContaining('needs Patron on either side'), findsOneWidget);
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
