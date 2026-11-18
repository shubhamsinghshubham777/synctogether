import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:synctogether/diagnostics.dart';

import 'room_service.dart';

/// What a pending action is, so the banner can word it and the lobby knows
/// where Undo should take the person.
enum PendingKind { deleteRoom, clearEnded, leaveRoom }

/// A thing the person did that only affects them, applied to the screen at once
/// while the server call waits out a short Undo window.
///
/// [commit] is the server call. It may throw: the failure becomes
/// [PendingActions.failure], a "couldn't finish" banner with Try again, and the
/// action is rolled back in the UI through [rollback].
class PendingAction {
  PendingAction({
    required this.kind,
    required this.title,
    required this.commit,
    this.subtitle,
    this.roomId,
    this.roomName,
    this.hiddenRoomIds = const {},
    this.rollback,
    this.failureTitle,
  });

  final PendingKind kind;
  final String title;
  final String? subtitle;
  final String? roomId;
  final String? roomName;

  /// Rooms taken out of "Your tickets" for the length of the window. They come
  /// back on Undo or on failure, and are dropped for good once the call lands.
  final Set<String> hiddenRoomIds;
  final Future<void> Function() commit;
  final VoidCallback? rollback;
  final String? failureTitle;
}

/// A commit that failed and is now waiting to be retried by the person.
class PendingFailure {
  const PendingFailure({required this.title, required this.message, required this.retry});
  final String title;
  final String message;
  final VoidCallback retry;
}

/// Undo instead of confirm (board 95).
///
/// Owned by a singleton rather than by the lobby or the room because it must
/// outlive both: a leave starts inside the room's State, which is about to be
/// disposed, and a delete must still commit if the lobby goes away first.
///
/// One action holds the banner at a time. Starting a second commits the first
/// at once, so there is never a stack of countdowns. The window ends at the
/// timer, at an explicit dismiss, and whenever the app leaves the foreground:
/// the OS can end the process any moment after that, so the call is made first.
/// A process killed with no warning leaves a leave unfinished, which keeps the
/// membership - the safe failure.
class PendingActions extends ChangeNotifier with WidgetsBindingObserver {
  PendingActions({this.window = const Duration(seconds: 5)});
  static PendingActions instance = PendingActions();

  /// How long Undo is on offer.
  final Duration window;
  RoomService get rooms => RoomService.instance;

  /// Held back from the network while offline: retried on a timer and when the
  /// app is back in front.
  static const kOfflineRetry = Duration(seconds: 15);

  PendingAction? _current;
  PendingAction? get current => _current;
  DateTime? _startedAt;

  /// Set when a commit failed for a reason that is not the network.
  PendingFailure? _failure;
  PendingFailure? get failure => _failure;

  /// The last action replaced by a newer one, named in the banner so it does not
  /// seem to have vanished.
  String? _replacedTitle;
  String? get replacedTitle => _replacedTitle;

  /// Set while the current action's call could not reach the server.
  bool _waitingForNetwork = false;
  bool get waitingForNetwork => _waitingForNetwork;

  final List<PendingAction> _offline = [];
  Timer? _timer;
  Timer? _offlineTimer;
  bool _observing = false;

  bool get active => _current != null || _failure != null;

  /// Fraction of the window left, for the ring (1 -> 0).
  Duration get remaining {
    final start = _startedAt;
    if (start == null) return window;
    final left = window - DateTime.now().difference(start);
    return left.isNegative ? Duration.zero : left;
  }

  void start(PendingAction action) {
    _observe();
    // Newest wins; the previous one is final now.
    final previous = _current;
    if (previous != null) {
      _replacedTitle = previous.roomName;
      unawaited(_commit(previous));
    } else {
      _replacedTitle = null;
    }
    _failure = null;
    _waitingForNetwork = false;
    _current = action;
    _startedAt = DateTime.now();
    if (action.hiddenRoomIds.isNotEmpty) rooms.hideRooms(action.hiddenRoomIds);
    trace(
      'undo window opened',
      category: 'room',
      data: {'kind': action.kind.name, 'room_id': action.roomId, 'window_s': window.inSeconds},
    );
    _timer?.cancel();
    _timer = Timer(window, () => unawaited(commitNow()));
    notifyListeners();
  }

  /// The person took it back. Returns what was pending so the caller can finish
  /// the job (a leave navigates back into the room), or null if nothing was.
  PendingAction? undo() {
    final action = _current;
    if (action == null) return null;
    _timer?.cancel();
    _current = null;
    _startedAt = null;
    _replacedTitle = null;
    rooms.unhideRooms(action.hiddenRoomIds);
    action.rollback?.call();
    trace('undo taken', category: 'room', data: {'kind': action.kind.name});
    notifyListeners();
    return action;
  }

  /// A leave is not final until it commits, so walking back into the room some
  /// other way (its ticket, an invite) must cancel it. Without this the call
  /// would land a few seconds later and drop the membership under a live session.
  void cancelLeave(String roomId) {
    final action = _current;
    if (action != null && action.kind == .leaveRoom && action.roomId == roomId) {
      _timer?.cancel();
      _current = null;
      _startedAt = null;
      trace('pending leave cancelled by re-entry', category: 'room', data: {'room_id': roomId});
      notifyListeners();
    }
    _offline.removeWhere((a) => a.kind == .leaveRoom && a.roomId == roomId);
  }

  /// Ends the window now (banner dismissed, timer ran out, app backgrounded).
  Future<void> commitNow() async {
    _timer?.cancel();
    final action = _current;
    if (action == null) return;
    _current = null;
    _startedAt = null;
    notifyListeners();
    await _commit(action);
  }

  Future<void> _commit(PendingAction action) async {
    try {
      await action.commit();
      rooms.unhideRooms(action.hiddenRoomIds);
      _waitingForNetwork = false;
      trace('pending action committed', category: 'room', data: {'kind': action.kind.name});
      // A leave deletes your membership, so the list the lobby is holding (and the
      // "Jump back in" strip built from it) is now out of date.
      if (action.kind == .leaveRoom) unawaited(_refreshRooms());
    } catch (e, s) {
      if (isTransientNetworkError(e)) {
        // Offline: keep it hidden and queued; Undo stays free until it lands.
        _offline.add(action);
        _current ??= action;
        _waitingForNetwork = true;
        _startedAt = DateTime.now();
        trace(
          'pending action waiting for network',
          category: 'room',
          data: {'kind': action.kind.name},
        );
        _offlineTimer ??= Timer.periodic(kOfflineRetry, (_) => unawaited(_retryOffline()));
        notifyListeners();
        return;
      }
      rooms.unhideRooms(action.hiddenRoomIds);
      action.rollback?.call();
      reportNonFatal(e, s, during: 'finishing a ${action.kind.name} after its undo window');
      _failure = PendingFailure(
        title: action.failureTitle ?? "Couldn't finish that",
        message: action.kind == .leaveRoom
            ? 'You are still a member. Open it from Your tickets to leave again.'
            : "It's back in your list. Check your connection and try again.",
        retry: () {
          _failure = null;
          start(action);
        },
      );
      notifyListeners();
    }
  }

  Future<void> _refreshRooms() async {
    try {
      await rooms.loadMyRooms();
    } catch (e) {
      // The lobby's own poll will catch up; nothing depends on this one.
      trace(
        'room list refresh after a leave failed',
        category: 'room',
        data: {'error': '${e.runtimeType}'},
      );
    }
  }

  Future<void> _retryOffline() async {
    if (_offline.isEmpty) {
      _offlineTimer?.cancel();
      _offlineTimer = null;
      return;
    }
    final queued = List<PendingAction>.of(_offline);
    _offline.clear();
    if (_current != null && queued.contains(_current)) _current = null;
    for (final action in queued) {
      await _commit(action);
    }
    if (_offline.isEmpty) {
      _offlineTimer?.cancel();
      _offlineTimer = null;
      _waitingForNetwork = false;
      notifyListeners();
    }
  }

  void dismissFailure() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }

  void _observe() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        // Before the process can go: this is the last moment we are sure to run.
        if (_current != null && !_waitingForNetwork) {
          trace('undo window ended by backgrounding', category: 'room');
          unawaited(commitNow());
        }
      case AppLifecycleState.resumed:
        if (_offline.isNotEmpty) unawaited(_retryOffline());
      default:
        break;
    }
  }

  void resetForTest() {
    _timer?.cancel();
    _offlineTimer?.cancel();
    _offlineTimer = null;
    _current = null;
    _failure = null;
    _offline.clear();
    _waitingForNetwork = false;
    _replacedTitle = null;
    _startedAt = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }
}
