import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/pairing/pair_links.dart';
import 'package:synctogether/pairing/push_service.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/reveal.dart';

/// "Someone took a seat" while the app is open (board 93): the same news as the
/// push, as a banner with Join on whatever screen the host is looking at.
///
/// The native side hands the push here and suppresses the system banner, so
/// there is one copy, not two. An overlay rather than a route, like the
/// discovery banners, so it never disturbs navigation.
class SeatTakenHost extends StatefulWidget {
  const SeatTakenHost({super.key, required this.router, required this.onJoin, required this.child});

  final GoRouter router;

  /// Goes to the room, leaving the one the person is in (if any).
  final Future<void> Function(String roomId) onJoin;
  final Widget child;

  @override
  State<SeatTakenHost> createState() => _SeatTakenHostState();
}

class _SeatTakenHostState extends State<SeatTakenHost> {
  StreamSubscription<ForegroundPush>? _sub;
  ForegroundPush? _shown;
  String? _roomId;

  /// How long the banner waits before it folds away on its own.
  static const _stay = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _sub = PushService.instance.foreground.listen(_onPush);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onPush(ForegroundPush push) {
    if (push.kind != 'seat_taken' || !AuthService.instance.isSignedIn) return;
    final target = pushTargetForRoute(push.route);
    if (target is! OpenRoom) return;
    // Already in that room: the news is the room itself.
    final here = widget.router.routerDelegate.currentConfiguration.uri.path;
    if (here == push.route) return;
    trace('seat taken banner shown', category: 'room', data: {'room_id': target.roomId});
    if (mounted) {
      setState(() {
        _shown = push;
        _roomId = target.roomId;
      });
    }
  }

  void _dismiss() {
    if (mounted) setState(() => _shown = null);
  }

  @override
  Widget build(BuildContext context) {
    final push = _shown;
    final pad = MediaQuery.paddingOf(context);
    final top = pad.top + (isDesktop ? 60 : 8);
    return Stack(
      fit: StackFit.expand,
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned(
          top: top,
          left: 16 + pad.left,
          right: 16 + pad.right,
          child: Material(
            type: MaterialType.transparency,
            // heightFactor: size to the banner, or the Center fills the screen
            // and parks it mid-page.
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: PTRevealKeep(
                  visible: push != null,
                  child: push == null ? const SizedBox(width: double.infinity) : _banner(push),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _banner(ForegroundPush push) {
    const tail = ' Tap to join them.';
    final body = push.body.endsWith(tail)
        ? push.body.substring(0, push.body.length - tail.length)
        : push.body;
    return PTEntrance(
      key: ValueKey('seat-${identityHashCode(push)}'),
      offset: -8,
      duration: PTMotion.state,
      child: PTBanner(
        kind: .info,
        icon: BoothIcons.group,
        title: push.title,
        subtitle: body,
        autoDismissAfter: _stay,
        onDismiss: _dismiss,
        trailing: PTButton(
          label: 'Join',
          variant: .secondary,
          height: 34,
          expand: false,
          onPressed: () {
            final id = _roomId;
            _dismiss();
            if (id != null) unawaited(widget.onJoin(id));
          },
        ),
      ),
    );
  }
}
