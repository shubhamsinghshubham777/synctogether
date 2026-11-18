import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/pending_actions.dart';
import 'package:synctogether/rooms/room_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PendingActions pending;
  late List<String> calls;

  PendingAction action(
    String id, {
    PendingKind kind = PendingKind.deleteRoom,
    Future<void> Function()? commit,
    Set<String>? hidden,
  }) => PendingAction(
    kind: kind,
    title: 'Deleted $id',
    roomId: id,
    roomName: id,
    hiddenRoomIds: hidden ?? {id},
    commit:
        commit ??
        () async {
          calls.add('commit $id');
        },
  );

  setUp(() {
    RoomService.instance = RoomService();
    pending = PendingActions.instance = PendingActions();
    calls = [];
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() {
      FlutterError.onError = previous;
      pending.resetForTest();
    });
  });

  test('waiting out the window makes exactly one call', () {
    fakeAsync((async) {
      pending.start(action('a'));
      expect(pending.current, isNotNull);
      async.elapse(const Duration(seconds: 4, milliseconds: 900));
      expect(calls, isEmpty, reason: 'Undo is still on offer');
      async.elapse(const Duration(milliseconds: 200));
      async.flushMicrotasks();
      expect(calls, ['commit a']);
      expect(pending.current, isNull);
    });
  });

  test('undo inside the window means the server is never called', () {
    fakeAsync((async) {
      pending.start(action('a'));
      final undone = pending.undo();
      expect(undone?.roomId, 'a');
      async.elapse(const Duration(seconds: 10));
      expect(calls, isEmpty);
      expect(pending.current, isNull);
    });
  });

  test('the ticket is hidden for the window and back after undo', () {
    pending.start(action('a'));
    expect(RoomService.instance.myRooms, isEmpty);
    pending.undo();
    // Nothing was loaded, so the observable part is that unhide notifies.
    var notified = 0;
    RoomService.instance.addListener(() => notified++);
    pending.start(action('b'));
    pending.undo();
    expect(notified, 2, reason: 'hide and unhide each notify');
  });

  test('backgrounding commits at once instead of waiting', () {
    fakeAsync((async) {
      pending.start(action('a'));
      pending.didChangeAppLifecycleState(AppLifecycleState.paused);
      async.flushMicrotasks();
      expect(calls, ['commit a']);
    });
  });

  test('a second action commits the first immediately; only one banner', () {
    fakeAsync((async) {
      pending.start(action('a'));
      pending.start(action('b'));
      async.flushMicrotasks();
      expect(calls, ['commit a']);
      expect(pending.current?.roomId, 'b');
      expect(pending.replacedTitle, 'a');
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(calls, ['commit a', 'commit b']);
    });
  });

  test('a failed call rolls back, reports friendly copy, and Try again re-opens the window', () {
    fakeAsync((async) {
      var attempts = 0;
      pending.start(
        action(
          'a',
          commit: () async {
            attempts++;
            if (attempts == 1) throw StateError('boom');
            calls.add('commit a');
          },
        ),
      );
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      final failure = pending.failure;
      expect(failure, isNotNull);
      expect(failure!.message, isNot(contains('boom')), reason: 'never raw error text');
      expect(pending.current, isNull);
      failure.retry();
      expect(pending.current, isNotNull, reason: 'a fresh window');
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(calls, ['commit a']);
      expect(pending.failure, isNull);
    });
  });

  test('offline keeps it queued with Undo available, and finishes when the network is back', () {
    fakeAsync((async) {
      var online = false;
      pending.start(
        action(
          'a',
          commit: () async {
            if (!online) throw const SocketException('down');
            calls.add('commit a');
          },
        ),
      );
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(pending.waitingForNetwork, isTrue);
      expect(pending.current, isNotNull, reason: 'Undo is still free');
      expect(pending.failure, isNull, reason: 'offline is not a failure');
      online = true;
      async.elapse(PendingActions.kOfflineRetry);
      async.flushMicrotasks();
      expect(calls, ['commit a']);
      expect(pending.waitingForNetwork, isFalse);
    });
  });

  test('walking back into the room cancels a pending leave', () {
    fakeAsync((async) {
      pending.start(action('r', kind: PendingKind.leaveRoom, hidden: {}));
      pending.cancelLeave('r');
      async.elapse(const Duration(seconds: 10));
      expect(calls, isEmpty);
      expect(pending.current, isNull);
    });
  });

  test('re-entering a different room leaves the pending leave alone', () {
    fakeAsync((async) {
      pending.start(action('r', kind: PendingKind.leaveRoom, hidden: {}));
      pending.cancelLeave('other');
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(calls, ['commit r']);
    });
  });
}
