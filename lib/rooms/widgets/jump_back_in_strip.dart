import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:synctogether/rooms/jump_back_in.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/reveal.dart';

/// Why a strip that was showing has gone, said once so it does not seem to
/// have vanished.
enum _Gone { ended, removed }

/// A ticket-stub strip at the top of the phone lobby: a room you are a member of
/// is live with somebody else in it and you are not inside (board 92).
///
/// Every state in the board is here: one room, a stack of two or more, a timed
/// session about to end, joining, a join that failed, a list that may be out of
/// date, and the strip's own exit (the room ended, or you were removed).
class JumpBackInStrip extends StatefulWidget {
  const JumpBackInStrip({
    super.key,
    required this.rooms,
    required this.allRooms,
    required this.serverNow,
    required this.onJump,
    required this.onViewTickets,
    this.joiningRoomId,
    this.failures = 0,
    this.onDismissFailure,
    this.stale = false,
    this.staleSince,
    this.leavingRoomIds = const {},
  });

  /// Eligible rooms, newest first (see [jumpBackInRooms]).
  final List<MyRoom> rooms;

  /// The whole list, so a room that left [rooms] can be explained.
  final List<MyRoom> allRooms;
  final DateTime serverNow;
  final ValueChanged<MyRoom> onJump;
  final VoidCallback onViewTickets;
  final String? joiningRoomId;

  /// Consecutive failed joins. One offers Try again; two also point at Your tickets.
  final int failures;
  final VoidCallback? onDismissFailure;

  /// The last refresh failed: the strip dims and stops offering a tap that would fail.
  final bool stale;
  final DateTime? staleSince;
  final Set<String> leavingRoomIds;

  @override
  State<JumpBackInStrip> createState() => _JumpBackInStripState();
}

class _JumpBackInStripState extends State<JumpBackInStrip> {
  _Gone? _gone;
  String? _goneName;
  Timer? _goneTimer;

  @override
  void didUpdateWidget(JumpBackInStrip old) {
    super.didUpdateWidget(old);
    final nowIds = {for (final r in widget.rooms) r.room.id};
    for (final before in old.rooms) {
      if (nowIds.contains(before.room.id)) continue;
      if (widget.leavingRoomIds.contains(before.room.id)) continue;
      final still = widget.allRooms.where((r) => r.room.id == before.room.id).firstOrNull;
      // Still live with people in it can't happen here (it would be in rooms);
      // still live and empty just means everyone left: nothing to explain.
      if (still != null && still.isLive) continue;
      _explain(still == null ? _Gone.removed : _Gone.ended, before.room.name);
      break;
    }
  }

  void _explain(_Gone reason, String name) {
    _goneTimer?.cancel();
    setState(() {
      _gone = reason;
      _goneName = name;
    });
    _goneTimer = Timer(const Duration(seconds: 8), _clearGone);
  }

  void _clearGone() {
    _goneTimer?.cancel();
    if (mounted) setState(() => _gone = null);
  }

  @override
  void dispose() {
    _goneTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.rooms;
    final failing = widget.failures > 0;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        PTRevealKeep(
          visible: rooms.isNotEmpty,
          gap: 18,
          child: rooms.isEmpty ? const SizedBox.shrink() : _strip(context, rooms),
        ),
        PTRevealKeep(
          visible: rooms.isNotEmpty && failing,
          gap: 10,
          child: PTBanner(
            kind: .error,
            icon: BoothIcons.alert,
            title: "Couldn't get you back in",
            subtitle: widget.failures > 1
                ? 'Your seat is still held. You can also open the room from Your tickets.'
                : 'Your seat is still held. Check your connection and try again.',
            onDismiss: widget.onDismissFailure,
            trailing: Row(
              mainAxisSize: .min,
              spacing: 8,
              children: [
                if (widget.failures > 1)
                  PTButton(
                    label: 'Your tickets',
                    variant: .secondary,
                    height: 34,
                    expand: false,
                    onPressed: widget.onViewTickets,
                  ),
                if (rooms.isNotEmpty)
                  PTButton(
                    label: 'Try again',
                    variant: .secondary,
                    height: 34,
                    expand: false,
                    onPressed: () => widget.onJump(rooms.first),
                  ),
              ],
            ),
          ),
        ),
        PTRevealKeep(
          visible: _gone != null,
          gap: 10,
          child: PTBanner(
            kind: .info,
            icon: _gone == _Gone.removed ? BoothIcons.leave : BoothIcons.info,
            title: _gone == _Gone.removed
                ? "You're no longer in ${_goneName ?? 'that room'}"
                : '${_goneName ?? 'That room'} just ended',
            subtitle: _gone == _Gone.removed
                ? "The host removed you, so there's no seat to jump back to."
                : "It's under Your tickets if you want to open it again.",
            onDismiss: _clearGone,
          ),
        ),
      ],
    );
  }

  Widget _strip(BuildContext context, List<MyRoom> rooms) {
    final front = rooms.first;
    final stacked = rooms.length > 1;
    final ending = endingSoonMinutes(front, widget.serverNow);
    final joining = widget.joiningRoomId == front.room.id;
    final stale = widget.stale;
    final people = '${othersIn(front)} IN';

    final String label;
    final String? sub;
    if (stale) {
      final since = widget.staleSince;
      final mins = since == null ? null : DateTime.now().difference(since).inMinutes;
      label = mins == null || mins < 1 ? 'MAY BE OUT OF DATE' : 'STALE · $mins MIN AGO';
      sub = null;
    } else if (stacked) {
      label = '${rooms.length} ROOMS LIVE';
      sub = 'NEWEST FIRST · $people';
    } else if (ending != null) {
      label = 'ENDS IN $ending MIN';
      sub = people;
    } else {
      label = 'NOW SHOWING · $people';
      sub = null;
    }

    final ink = PTColors.canvas;
    final muted = ink.withValues(alpha: 0.62);
    final signal = stale ? muted : PTColors.liveInk;

    final ticket = PTTicket(
      paper: true,
      stubWidth: 124,
      onTap: stale || joining
          ? null
          : (stacked ? widget.onViewTickets : () => widget.onJump(front)),
      semanticLabel:
          '${front.room.name}, live, ${othersIn(front)} ${othersIn(front) == 1 ? 'person' : 'people'} in'
          '${stacked ? ', and ${rooms.length - 1} more' : ''}',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          spacing: 3,
          children: [
            Row(
              spacing: 6,
              children: [
                if (!stale)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: signal, shape: .circle),
                  ),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: PTText.label.copyWith(fontSize: 10, color: signal),
                  ),
                ),
              ],
            ),
            Text(
              front.room.name,
              maxLines: 1,
              overflow: .ellipsis,
              style: PTText.cardHeading.copyWith(fontSize: 17, color: ink),
            ),
            if (sub != null)
              Text(
                sub,
                maxLines: 1,
                overflow: .ellipsis,
                style: PTText.mono.copyWith(fontSize: 10, color: muted),
              ),
          ],
        ),
      ),
      stub: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Center(
          child: _jumpButton(front, joining: joining, stale: stale),
        ),
      ),
    );

    final dimmed = stale ? Opacity(opacity: 0.6, child: ticket) : ticket;
    if (!stacked) return dimmed;
    // A second stub peeking out under the first, inset and a shade darker, so a
    // pair of live rooms reads as a small stack rather than as the same strip.
    final under = Color.lerp(PTColors.fg, PTColors.canvas, 0.3)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Stack(
        clipBehavior: .none,
        children: [
          Positioned(
            left: 12,
            right: 12,
            bottom: -10,
            height: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: under,
                borderRadius: BorderRadius.circular(PTRadius.panel),
              ),
            ),
          ),
          dimmed,
        ],
      ),
    );
  }

  Widget _jumpButton(MyRoom room, {required bool joining, required bool stale}) {
    final label = stale ? 'Offline' : (joining ? 'Joining' : 'Jump back in');
    final enabled = !stale && !joining;
    return PTPressable(
      enabled: enabled,
      onTap: enabled ? () => widget.onJump(room) : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: enabled ? PTColors.canvas : PTColors.canvas.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(PTRadius.control),
          border: enabled ? null : Border.all(color: PTColors.canvas.withValues(alpha: 0.3)),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: .scaleDown,
          child: Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              if (joining) const PTLoader(size: 14, color: PTColors.fg),
              Text(
                label,
                maxLines: 1,
                style: PTText.buttonLabel.copyWith(
                  color: enabled || joining ? PTColors.fg : PTColors.canvas.withValues(alpha: 0.55),
                  fontWeight: .w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
