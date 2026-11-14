import 'package:flutter/widgets.dart';

/// The controls a first-night coach mark can point at.
enum CoachTargetId {
  /// The lobby's "Open a room" submit button.
  openRoom,

  /// The empty room's "Choose a video" / "Paste a YouTube link" button.
  pickSource,

  /// The room code chip in the room's header.
  roomCode,

  /// The play/pause button in the room's control bar.
  play,
}

/// Marks a control so a [CoachMark] can find its rectangle. Like
/// `DiscoveryAnchor`, several of the same id can be mounted at once (a layout
/// swap mid-frame, or the room's header and pill); the newest wins.
///
/// [onActivate] is what the card's primary button does when it names this
/// control's action ("Open a room"): it runs the control's own handler, so the
/// mark never re-implements the action.
class CoachTarget extends StatefulWidget {
  const CoachTarget({super.key, required this.id, required this.child, this.onActivate});

  final CoachTargetId id;
  final Widget child;
  final VoidCallback? onActivate;

  static final Map<CoachTargetId, List<_CoachTargetState>> _mounted = {};

  /// Bumped whenever a target mounts or unmounts, so a waiting coach can retry.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static _CoachTargetState? _top(CoachTargetId id) {
    final list = _mounted[id];
    return (list == null || list.isEmpty) ? null : list.last;
  }

  /// The newest mounted [id]'s rectangle in window coordinates, or null when
  /// none is mounted, laid out, or it has no visible size.
  static Rect? rectOf(CoachTargetId id) {
    final box = _top(id)?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  static bool isMounted(CoachTargetId id) => rectOf(id) != null;

  /// Runs the newest mounted [id]'s [onActivate], if it has one.
  static void activate(CoachTargetId id) => _top(id)?.widget.onActivate?.call();

  @override
  State<CoachTarget> createState() => _CoachTargetState();
}

class _CoachTargetState extends State<CoachTarget> {
  @override
  void initState() {
    super.initState();
    (CoachTarget._mounted[widget.id] ??= []).add(this);
    _notify();
  }

  @override
  void didUpdateWidget(CoachTarget old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      CoachTarget._mounted[old.id]?.remove(this);
      (CoachTarget._mounted[widget.id] ??= []).add(this);
      _notify();
    }
  }

  @override
  void dispose() {
    CoachTarget._mounted[widget.id]?.remove(this);
    _notify();
    super.dispose();
  }

  void _notify() {
    // Notifying mid-build/unmount is illegal; hop to the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => CoachTarget.changes.value++);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
