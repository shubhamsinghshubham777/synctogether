import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics.dart';
import '../ui/coach_mark.dart';
import '../ui/coach_target.dart';
import 'onboarding_logic.dart';

/// Which first-night coach marks are still owed on this device. Armed by the
/// flow when it finishes, cleared as each set plays. Local on purpose: the flow
/// itself is once per account, but the marks belong to the device it ran on.
class OnboardingCoach extends ChangeNotifier {
  OnboardingCoach({SharedPreferences? testPrefs}) : _prefs = testPrefs;

  static OnboardingCoach instance = OnboardingCoach();

  static const _kLobby = 'onboarding.lobby_mark';
  static const _kRoom = 'onboarding.room_marks';

  SharedPreferences? _prefs;

  Future<void> load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      notifyListeners();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading onboarding coach prefs');
    }
  }

  bool get lobbyMarkPending => _prefs?.getBool(_kLobby) ?? false;

  /// Null when no room marks are owed; else whether they arrived by invite.
  bool? get roomMarksInvited => switch (_prefs?.getString(_kRoom)) {
    'invite' => true,
    'host' => false,
    _ => null,
  };

  /// After the flow: the lobby mark (friends only) and the room marks.
  Future<void> arm({required bool lobbyMark, required bool invited}) async {
    await load();
    await _prefs?.setBool(_kLobby, lobbyMark);
    await _prefs?.setString(_kRoom, invited ? 'invite' : 'host');
    trace('onboarding coach armed', category: 'ui', data: {'lobby': lobbyMark, 'invited': invited});
    notifyListeners();
  }

  Future<void> clearLobbyMark() async {
    await _prefs?.setBool(_kLobby, false);
    notifyListeners();
  }

  Future<void> clearRoomMarks() async {
    await _prefs?.remove(_kRoom);
    notifyListeners();
  }
}

/// Draws the first-night coach marks above the whole app, like `DiscoveryHost`:
/// an overlay, not a route, so it never disturbs navigation. The lobby mark
/// shows only on the lobby itself (the lobby stays mounted under every nested
/// route, so its button alone is no proof the user can see it); the room marks
/// play once, in order, the first time a room settles.
class OnboardingCoachHost extends StatefulWidget {
  const OnboardingCoachHost({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  /// How long a room is left to lay out before its marks are picked, so a
  /// control that is about to appear (the control bar) is counted.
  static const settle = Duration(milliseconds: 900);

  @override
  State<OnboardingCoachHost> createState() => _OnboardingCoachHostState();
}

class _OnboardingCoachHostState extends State<OnboardingCoachHost> {
  OnboardingCoach get _c => OnboardingCoach.instance;

  /// The room marks being played, once picked; and which one is up.
  List<CoachTargetId>? _marks;
  int _index = 0;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    unawaited(_c.load());
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  String get _path => widget.router.routerDelegate.currentConfiguration.uri.path;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned.fill(
          child: ListenableBuilder(
            listenable: Listenable.merge([_c, widget.router.routerDelegate, CoachTarget.changes]),
            builder: (context, _) => _overlay(),
          ),
        ),
      ],
    );
  }

  Widget _overlay() {
    final path = _path;
    final inRoom = path.startsWith('/lobby/room/');
    if (!inRoom) {
      _leaveRoom();
      if (path == '/lobby' && _c.lobbyMarkPending && CoachTarget.isMounted(.openRoom)) {
        return _mark(
          id: .openRoom,
          copy: roomMarkCopy(.openRoom, 1, 1),
          doneLabel: 'Open a room',
          skipLabel: 'Not now',
          onEnd: (end) {
            trace('lobby coach mark ended', category: 'ui', data: {'end': end.name});
            unawaited(_c.clearLobbyMark());
            if (end == CoachEnd.done) CoachTarget.activate(.openRoom);
          },
        );
      }
      return const SizedBox.shrink();
    }

    final invited = _c.roomMarksInvited;
    if (invited == null) return const SizedBox.shrink();
    // Once a room's marks start, the lobby one is moot.
    if (_c.lobbyMarkPending) unawaited(_c.clearLobbyMark());
    final marks = _marks;
    if (marks == null) {
      _settle ??= Timer(OnboardingCoachHost.settle, () {
        if (!mounted) return;
        final picked = visibleRoomMarks(roomMarks(invited: invited), CoachTarget.isMounted);
        trace(
          'room coach marks picked',
          category: 'ui',
          data: {'marks': picked.map((m) => m.name).join(',')},
        );
        setState(() {
          _marks = picked;
          _index = 0;
        });
        if (picked.isEmpty) unawaited(_c.clearRoomMarks());
      });
      return const SizedBox.shrink();
    }
    if (_index >= marks.length) return const SizedBox.shrink();
    final id = marks[_index];
    // A control that went away mid-sequence (the source got picked) is skipped.
    if (!CoachTarget.isMounted(id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _next(marks));
      return const SizedBox.shrink();
    }
    final last = _index == marks.length - 1;
    return _mark(
      key: ValueKey('room-mark-$_index'),
      id: id,
      copy: roomMarkCopy(id, _index + 1, marks.length),
      doneLabel: last ? 'Got it' : 'Next',
      step: _index + 1,
      steps: marks.length,
      onEnd: (end) {
        // Next walks on; anything else (the dim, Escape, using the control
        // itself) ends the set - the user has what they need.
        if (end == CoachEnd.done && !last) {
          _next(marks);
        } else {
          trace(
            'room coach marks ended',
            category: 'ui',
            data: {'at': _index + 1, 'end': end.name},
          );
          setState(() => _index = marks.length);
          unawaited(_c.clearRoomMarks());
        }
      },
    );
  }

  void _next(List<CoachTargetId> marks) {
    if (!mounted) return;
    setState(() => _index++);
    if (_index >= marks.length) unawaited(_c.clearRoomMarks());
  }

  /// Leaving the room mid-way forgets the picked set (the marks themselves stay
  /// owed only if none was shown yet).
  void _leaveRoom() {
    _settle?.cancel();
    _settle = null;
    if (_marks != null) {
      _marks = null;
      _index = 0;
    }
  }

  Widget _mark({
    Key? key,
    required CoachTargetId id,
    required ({String kicker, String title, String body}) copy,
    required String doneLabel,
    required ValueChanged<CoachEnd> onEnd,
    String? skipLabel,
    int? step,
    int? steps,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          CoachMark(
            key: key ?? ValueKey(id),
            anchor: () => CoachTarget.rectOf(id),
            kicker: copy.kicker,
            title: copy.title,
            body: copy.body,
            doneLabel: doneLabel,
            skipLabel: skipLabel,
            step: step,
            steps: steps,
            onEnd: onEnd,
          ),
        ],
      ),
    );
  }
}
