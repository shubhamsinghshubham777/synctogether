import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/rooms/roster_fold.dart';
import 'package:synctogether/rooms/widgets/room_chat_panel.dart';
import 'package:synctogether/rooms/widgets/room_roster.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/rolling_text.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/pt_motion.dart';

import '../sync/fakes.dart';

const _key = 'pt.room.roster_collapsed';

List<ChatRosterSeat> _seats(int n, {int ready = 0}) => [
  for (var i = 0; i < n; i++)
    ChatRosterSeat(
      member: PresentMember(
        userId: 'u$i',
        displayName: 'Person $i',
        role: i == 0 ? 'host' : 'member',
        joinedAt: DateTime.utc(2026, 1, 1),
      ),
      ready: i < ready,
    ),
];

/// A rolling line (the +N), found by the whole string it shows.
Finder _rolling(String t) => find.byWidgetPredicate((w) => w is PTRollingText && w.text == t);

Finder get _toggle => find.bySemanticsLabel(RegExp(r'in the room, \d+ ready'));

Future<void> _pump(
  WidgetTester tester,
  RosterFold fold,
  List<ChatRosterSeat> seats, {
  double width = 390,
  double textScale = 1.0,
  bool reduceMotion = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: FoldableRoster(seats: seats, fold: fold),
            ),
          ),
        ),
      ),
    ),
  );
}

double _height(WidgetTester tester) => tester.getSize(find.byType(FoldableRoster)).height;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RosterFold', () {
    test('starts expanded and folds itself once, after everyone is ready', () {
      final fold = RosterFold(autoDelay: const Duration(milliseconds: 100));
      fold.observe(total: 3, ready: 3);
      expect(fold.collapsed, isFalse);
      return Future<void>.delayed(const Duration(milliseconds: 150)).then((_) {
        expect(fold.collapsed, isTrue);
        expect(fold.decided, isFalse, reason: 'an automatic fold is not a choice');
        fold.dispose();
      });
    });

    test('someone not ready keeps it open, and a late arrival cancels the pending fold', () async {
      final fold = RosterFold(autoDelay: const Duration(milliseconds: 100));
      fold.observe(total: 3, ready: 2);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(fold.collapsed, isFalse);
      fold.observe(total: 3, ready: 3);
      fold.observe(total: 4, ready: 3);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(fold.collapsed, isFalse, reason: 'the gate reopened before the fold landed');
      fold.dispose();
    });

    test('an empty room is not "everyone ready"', () async {
      final fold = RosterFold(autoDelay: const Duration(milliseconds: 50));
      fold.observe(total: 0, ready: 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fold.collapsed, isFalse);
      fold.dispose();
    });

    test('a manual toggle wins for the rest of the room', () async {
      final fold = RosterFold(autoDelay: const Duration(milliseconds: 50));
      fold.observe(total: 2, ready: 2);
      fold.toggle(); // the viewer folds it first
      fold.toggle(); // and opens it again
      expect(fold.collapsed, isFalse);
      fold.observe(total: 2, ready: 2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fold.collapsed, isFalse, reason: 'respect the choice');
      fold.dispose();
    });

    test('folding by hand is remembered; opening it clears the memory', () async {
      final a = RosterFold();
      a.toggle();
      await Future<void>.delayed(Duration.zero);
      expect((await SharedPreferences.getInstance()).getBool(_key), isTrue);

      final b = RosterFold();
      await b.load();
      expect(b.collapsed, isTrue, reason: 'the next room starts folded');
      expect(b.decided, isTrue);

      b.toggle();
      await Future<void>.delayed(Duration.zero);
      expect((await SharedPreferences.getInstance()).containsKey(_key), isFalse);

      final c = RosterFold();
      await c.load();
      expect(c.collapsed, isFalse, reason: 'a peek must not become "never fold it again"');
      expect(c.decided, isFalse);
      for (final f in [a, b, c]) {
        f.dispose();
      }
    });

    test('a remembered fold beats the gate being clear or not', () async {
      SharedPreferences.setMockInitialValues({_key: true});
      final fold = RosterFold(autoDelay: const Duration(milliseconds: 20));
      await fold.load();
      fold.observe(total: 3, ready: 1);
      expect(fold.collapsed, isTrue);
      fold.dispose();
    });
  });

  group('FoldableRoster', () {
    testWidgets('the toggle is a 44 px button that names the room and its state', (tester) async {
      final handle = tester.ensureSemantics();
      final fold = RosterFold();
      await _pump(tester, fold, _seats(4, ready: 3));
      final node = tester.getSemantics(_toggle);
      expect(node.label, '4 people in the room, 3 ready');
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isExpanded.toBoolOrNull(), isTrue);
      final row = tester.getRect(find.text('IN THE ROOM · 4'));
      final target = tester.getRect(
        find.ancestor(of: find.text('IN THE ROOM · 4'), matching: find.byType(PTPressable)),
      );
      expect(target.height, greaterThanOrEqualTo(44));
      expect(target.contains(row.center), isTrue);

      await tester.tap(find.text('IN THE ROOM · 4'));
      await tester.pumpAndSettle();
      expect(fold.collapsed, isTrue);
      expect(tester.getSemantics(_toggle).flagsCollection.isExpanded.toBoolOrNull(), isFalse);
      handle.dispose();
      fold.dispose();
    });

    testWidgets('one person reads as "1 person"', (tester) async {
      final fold = RosterFold();
      await _pump(tester, fold, _seats(1, ready: 1));
      expect(find.bySemanticsLabel('1 person in the room, 1 ready'), findsOneWidget);
      fold.dispose();
    });

    testWidgets('folded is a slim 44 px row and the height animates, never jumps', (tester) async {
      final fold = RosterFold();
      await _pump(tester, fold, _seats(4, ready: 3));
      final open = _height(tester);
      expect(open, greaterThan(90));

      fold.toggle();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = _height(tester);
      expect(mid, lessThan(open));
      expect(mid, greaterThan(46), reason: 'mid-fold is between the two forms');

      await tester.pumpAndSettle();
      final slim = _height(tester);
      expect(slim, inInclusiveRange(44, 46), reason: '44 px target + the hairline');

      // The hairline is still at the bottom, so the chat starts where it did.
      fold.toggle();
      await tester.pumpAndSettle();
      expect(_height(tester), open);
      fold.dispose();
    });

    testWidgets('folded: label, a stack of rings with +N, and an attention dot', (tester) async {
      final fold = RosterFold()..toggle();
      await _pump(tester, fold, _seats(8, ready: 5));
      await tester.pumpAndSettle();
      expect(find.text('IN THE ROOM · 8'), findsOneWidget);
      // Five small rings, then "+3".
      final mini = find.byWidgetPredicate((w) => w is ReadyRing && w.diameter == 20);
      expect(mini, findsNWidgets(5));
      expect(_rolling('+3'), findsOneWidget);
      // The ones the room is waiting on come first, so none hide behind +N.
      final states = mini.evaluate().map((e) => (e.widget as ReadyRing).ready);
      expect(states.where((r) => !r).length, 3);
      fold.dispose();
    });

    testWidgets('no dot, no waiting rings once everyone is ready', (tester) async {
      final fold = RosterFold()..toggle();
      await _pump(tester, fold, _seats(3, ready: 3));
      await tester.pumpAndSettle();
      final rings = find.byType(ReadyRing).evaluate().map((e) => (e.widget as ReadyRing).ready);
      expect(rings.every((r) => r), isTrue);
      expect(_rolling('+0'), findsNothing);
      fold.dispose();
    });

    testWidgets('folded rings are out of semantics and focus', (tester) async {
      final handle = tester.ensureSemantics();
      final fold = RosterFold()..toggle();
      await _pump(tester, fold, _seats(4, ready: 4));
      await tester.pumpAndSettle();
      // Whatever wraps the rings, and only that, is what the fold excludes.
      bool excluded<T extends Widget>(bool Function(T) test) => find
          .ancestor(of: find.byType(RosterRings), matching: find.byType(T))
          .evaluate()
          .any((e) => test(e.widget as T));
      expect(excluded<ExcludeSemantics>((w) => w.excluding), isTrue);
      expect(excluded<ExcludeFocus>((w) => w.excluding), isTrue);
      fold.toggle();
      await tester.pumpAndSettle();
      expect(excluded<ExcludeSemantics>((w) => w.excluding), isFalse);
      expect(excluded<ExcludeFocus>((w) => w.excluding), isFalse);
      handle.dispose();
      fold.dispose();
    });

    testWidgets('reduce motion still folds, in half the time', (tester) async {
      final fold = RosterFold();
      await _pump(tester, fold, _seats(4, ready: 4), reduceMotion: true);
      final open = _height(tester);
      fold.toggle();
      await tester.pump();
      await tester.pump(PTMotion.panel * 0.5 + const Duration(milliseconds: 10));
      expect(_height(tester), lessThan(open));
      expect(_height(tester), inInclusiveRange(44, 46));
      fold.dispose();
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      for (final width in [320.0, 390.0]) {
        testWidgets('no overflow at ${width}pt, text x$scale, both forms', (tester) async {
          final fold = RosterFold();
          await _pump(tester, fold, _seats(9, ready: 4), width: width, textScale: scale);
          await tester.pumpAndSettle();
          final open = _height(tester);
          fold.toggle();
          await tester.pumpAndSettle();
          final slim = _height(tester);
          expect(slim, lessThan(open));
          expect(slim, greaterThanOrEqualTo(44));
          expect(tester.takeException(), isNull);
          fold.dispose();
        });
      }
    }
  });

  group('RoomChatPanel', () {
    Future<void> pumpPanel(WidgetTester tester, RosterFold fold, List<ChatRosterSeat> seats) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 560,
              child: RoomChatPanel(
                sync: SyncServiceFactory.host(),
                messages: const [],
                typingNames: const [],
                watchingCount: seats.length,
                onClose: () {},
                onSend: (_) {},
                onCopied: () {},
                embedded: true,
                closable: false,
                roster: seats,
                rosterFold: fold,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('folds itself once the gate clears, then stays put', (tester) async {
      final fold = RosterFold(autoDelay: const Duration(milliseconds: 500));
      await pumpPanel(tester, fold, _seats(3, ready: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(fold.collapsed, isFalse);

      await pumpPanel(tester, fold, _seats(3, ready: 3));
      await tester.pump(const Duration(milliseconds: 400));
      expect(fold.collapsed, isFalse, reason: 'the rings get a beat to turn Cue first');
      await tester.pump(const Duration(milliseconds: 200));
      expect(fold.collapsed, isTrue);
      await tester.pumpAndSettle();

      // Somebody new, not ready: it does not pop back open by itself.
      await pumpPanel(tester, fold, _seats(4, ready: 3));
      await tester.pumpAndSettle();
      expect(fold.collapsed, isTrue);
      fold.dispose();
    });

    testWidgets('without a fold (desktop, floating) the roster is the plain header', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 330,
              height: 560,
              child: RoomChatPanel(
                sync: SyncServiceFactory.host(),
                messages: const [],
                typingNames: const [],
                watchingCount: 3,
                onClose: () {},
                onSend: (_) {},
                onCopied: () {},
                docked: true,
                roster: _seats(3, ready: 3),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FoldableRoster), findsNothing);
      expect(find.text('IN THE ROOM · 3'), findsOneWidget);
      expect(find.byType(RosterRings), findsOneWidget);
    });
  });
}

/// A host's [SyncService] over the fakes, as `room_chat_panel_test` builds one.
abstract final class SyncServiceFactory {
  static SyncService host() => SyncService(
    FakeSyncPlayer(),
    room: testRoom(),
    profile: testProfile('me'),
    role: 'host',
    backend: FakeSyncBackend(),
  );
}
