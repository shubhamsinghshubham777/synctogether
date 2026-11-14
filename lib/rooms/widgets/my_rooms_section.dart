import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../ui/reveal.dart';
import '../../ui/optical.dart';
import '../../ui/booth_icons.g.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// List width at which room tickets pair up into two columns.
const double kTicketTwoColumnWidth = 720;

class MyRoomsSection extends StatelessWidget {
  const MyRoomsSection({
    super.key,
    required this.rooms,
    required this.serverNow,
    required this.onOpen,
    required this.onDelete,
    required this.busyRoomId,
    this.onClearEnded,
    this.clearingEnded = false,
    this.compact = false,
    this.framed = true,
  });

  /// False drops the panel and uses the mono label heading - for a column
  /// that is already its own surface (the desktop lobby's right side).
  final bool framed;

  final List<MyRoom> rooms;
  final DateTime serverNow;
  final ValueChanged<MyRoom> onOpen;
  final ValueChanged<MyRoom> onDelete;
  final ValueChanged<List<MyRoom>>? onClearEnded;
  final bool clearingEnded;
  final String? busyRoomId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final endedRooms = rooms.where((r) => !r.isLive && !r.room.persistent && r.isOwner).toList();

    final body = Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: compact ? 14 : 18,
      children: [
        Row(
          children: [
            if (!framed)
              Expanded(
                child: Text(
                  'YOUR TICKETS · ${rooms.length}',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.label,
                ),
              )
            else ...[
              Icon(
                Symbols.meeting_room_rounded,
                size: compact ? 20 : 22,
                fill: 1,
                color: PTColors.textAccent,
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Text.rich(
                  maxLines: 1,
                  overflow: .ellipsis,
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Your tickets',
                        style: compact
                            ? PTText.cardHeading.copyWith(fontSize: 16)
                            : PTText.cardHeading.copyWith(fontSize: 18),
                      ),
                      TextSpan(
                        text: ' (${rooms.length})',
                        style: PTText.mono.copyWith(
                          fontSize: compact ? 13 : 14,
                          color: PTColors.white(0.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // Unfolds in beside the title once there is something to clear, and folds
            // away when the last ended room goes.
            PTRevealKeep(
              visible: endedRooms.isNotEmpty,
              axis: Axis.horizontal,
              alignment: Alignment.centerRight,
              gap: compact ? 8 : 10,
              child: _ClearEndedButton(
                count: endedRooms.length,
                compact: compact,
                busy: clearingEnded,
                onPressed: onClearEnded != null && !clearingEnded
                    ? () => onClearEnded!(endedRooms)
                    : null,
              ),
            ),
          ],
        ),
        // Tickets pair up once each can keep a readable name beside its
        // stub; below that they stack. A list, not a wrapped row, so a
        // resize re-deals whole tickets rather than reflowing their insides.
        _TicketList(
          rooms: rooms,
          serverNow: serverNow,
          compact: compact,
          busyRoomId: busyRoomId,
          onOpen: onOpen,
          onDelete: onDelete,
        ),
      ],
    );
    if (!framed) return body;
    return GlassPanel(padding: EdgeInsets.all(compact ? 20 : 28), child: body);
  }
}

/// The tickets. A ticket that goes (deleted, cleared, or its room ended and was swept)
/// folds shut where it stood while the ones below glide up, instead of vanishing and
/// the list jumping; a new one still arrives with the entrance it always had.
class _TicketList extends StatefulWidget {
  const _TicketList({
    required this.rooms,
    required this.serverNow,
    required this.compact,
    required this.busyRoomId,
    required this.onOpen,
    required this.onDelete,
  });

  final List<MyRoom> rooms;
  final DateTime serverNow;
  final bool compact;
  final String? busyRoomId;
  final ValueChanged<MyRoom> onOpen;
  final ValueChanged<MyRoom> onDelete;

  @override
  State<_TicketList> createState() => _TicketListState();
}

class _Slot {
  const _Slot(this.id, this.entry, {this.leaving = false});

  final String id;
  final MyRoom entry;
  final bool leaving;
}

class _TicketListState extends State<_TicketList> {
  List<_Slot> _slots = [];
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _slots = [for (final r in widget.rooms) _Slot(r.room.id, r)];
  }

  @override
  void didUpdateWidget(_TicketList old) {
    super.didUpdateWidget(old);
    final next = [for (final r in widget.rooms) _Slot(r.room.id, r)];
    var anchor = -1;
    for (final old in _slots) {
      final i = next.indexWhere((s) => s.id == old.id);
      if (i >= 0) {
        anchor = i;
        continue;
      }
      // Gone from the list: keep it, folding out, where it was.
      anchor += 1;
      next.insert(anchor.clamp(0, next.length), _Slot(old.id, old.entry, leaving: true));
      if (!old.leaving) {
        _timers.add(
          Timer(PTMotion.state * 1.2, () {
            if (!mounted) return;
            setState(
              () => _slots = [
                for (final s in _slots)
                  if (!(s.leaving && s.id == old.id)) s,
              ],
            );
          }),
        );
      }
    }
    _slots = next;
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tickets pair up once each can keep a readable name beside its stub; below that
    // they stack. A list, not a wrapped row, so a resize re-deals whole tickets
    // rather than reflowing their insides.
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= kTicketTwoColumnWidth ? 2 : 1;
        final tickets = [
          for (final (index, slot) in _slots.indexed)
            PTReveal(
              key: ValueKey('fold-${slot.id}'),
              visible: !slot.leaving,
              // The gap above a ticket travels with it, so a folded one leaves none.
              child: Padding(
                padding: EdgeInsets.only(top: index >= columns ? 10 : 0),
                child: PTEntrance(
                  key: ValueKey(slot.id),
                  delay: Duration(milliseconds: 40 * index),
                  duration: PTMotion.state,
                  offset: 8,
                  fade: false,
                  child: _RoomRow(
                    entry: slot.entry,
                    serverNow: widget.serverNow,
                    compact: widget.compact || columns == 2,
                    busy: widget.busyRoomId == slot.id,
                    onOpen: () => widget.onOpen(slot.entry),
                    onDelete: () => widget.onDelete(slot.entry),
                  ),
                ),
              ),
            ),
        ];
        return Column(
          mainAxisSize: .min,
          children: [
            for (var i = 0; i < tickets.length; i += columns)
              Row(
                crossAxisAlignment: .start,
                children: [
                  for (var j = i; j < i + columns; j++) ...[
                    if (j > i) const SizedBox(width: 10),
                    Expanded(child: j < tickets.length ? tickets[j] : const SizedBox()),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }
}

class _RoomRow extends StatefulWidget {
  const _RoomRow({
    required this.entry,
    required this.serverNow,
    required this.compact,
    required this.busy,
    required this.onOpen,
    required this.onDelete,
  });

  final MyRoom entry;
  final DateTime serverNow;
  final bool compact;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<_RoomRow> createState() => _RoomRowState();
}

class _RoomRowState extends State<_RoomRow> {
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final room = entry.room;
    final live = entry.isLive;
    final compact = widget.compact;
    // Paper is for what is showing now; everything else is a dark ticket on
    // the booth. The fill tweens between the two when a room ends under you.
    final ink = live ? PTColors.canvas : PTColors.fg;
    final muted = ink.withValues(alpha: live ? 0.62 : 0.55);

    return PTTicket(
      paper: live,
      stubWidth: compact ? 92 : 116,
      onTap: widget.busy ? null : widget.onOpen,
      semanticLabel: '${room.name}, ${_eyebrow(entry)}',
      body: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 16 : 20, 14, 12, 14),
        child: Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          spacing: 5,
          children: [
            Row(
              spacing: 6,
              children: [
                if (live)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(color: PTColors.liveInk, shape: .circle),
                  ),
                Flexible(
                  child: Text(
                    _eyebrow(entry).toUpperCase(),
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: PTText.label.copyWith(
                      fontSize: 10,
                      color: live ? PTColors.liveInk : muted,
                    ),
                  ),
                ),
              ],
            ),
            // The badge may take at most 40% of the line and scales down past
            // that: a narrow tile at 2x text (split view, SE landscape) would
            // otherwise push it off the edge.
            LayoutBuilder(
              builder: (context, box) => Row(
                spacing: 8,
                children: [
                  Flexible(
                    child: Text(
                      room.name,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: PTText.cardHeading.copyWith(
                        fontSize: compact ? 17 : 19,
                        color: live ? ink : PTColors.white(0.8),
                      ),
                    ),
                  ),
                  if (_badge(live, entry.isHost) case final badge?)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: box.maxWidth * 0.4),
                      child: FittedBox(fit: .scaleDown, child: badge),
                    ),
                ],
              ),
            ),
            Text(
              _subtitle(entry, widget.serverNow),
              maxLines: 1,
              overflow: .ellipsis,
              style: PTText.mono.copyWith(fontSize: 11, color: muted),
            ),
          ],
        ),
      ),
      stub: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Column(
          mainAxisAlignment: .center,
          spacing: 6,
          children: [
            FittedBox(
              fit: .scaleDown,
              child: Text(
                room.code.toUpperCase(),
                maxLines: 1,
                style: PTText.mono.copyWith(
                  fontSize: compact ? 13 : 15,
                  fontWeight: .w600,
                  letterSpacing: 1.2,
                  color: live ? ink : PTColors.white(0.7),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: PTMotion.functional(context, PTMotion.state),
              child: widget.busy
                  ? const SizedBox(key: ValueKey('busy'), height: 30, child: PTLoader(size: 16))
                  : PTIconButton(
                      key: const ValueKey('delete'),
                      icon: BoothIcons.ticketDelete,
                      size: 30,
                      iconSize: 16,
                      glass: false,
                      color: live ? PTColors.canvas.withValues(alpha: 0.6) : null,
                      tooltip: entry.isOwner
                          ? 'Delete room'
                          : 'Only the person who made this room can delete it',
                      onPressed: entry.isOwner ? widget.onDelete : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _eyebrow(MyRoom entry) {
    if (entry.isIdle) return 'Resting · saved';
    if (!entry.isLive) return 'Ended';
    if (entry.room.persistent) return 'Saved · ${entry.memberCount} in';
    return 'Now showing · ${entry.memberCount} in';
  }

  static Widget? _badge(bool live, bool isHost) {
    if (live && isHost) {
      // Inverted tag: ink on paper, the host's plate on the ticket.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: PTColors.canvas, borderRadius: BorderRadius.circular(2)),
        child: Text(
          'HOST',
          style: PTText.label.copyWith(fontSize: 9, color: PTColors.fg, letterSpacing: 1),
        ),
      );
    }
    return null;
  }

  static String _subtitle(MyRoom entry, DateTime serverNow) {
    final room = entry.room;
    final people = '${entry.memberCount} ${entry.memberCount == 1 ? 'watcher' : 'watchers'}';
    if (entry.isIdle) {
      return entry.isHost ? 'Between sessions · tap to start' : 'Waiting for the host to start';
    }
    if (room.persistent) return '$people · saved';
    if (entry.isLive) {
      return '$people · ${_left(room.expiresAt.difference(serverNow))} left';
    }
    return 'Session over · tap for options';
  }

  static String _left(Duration d) {
    if (d.isNegative) return 'moments';
    if (d.inHours >= 24) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    return '${d.inMinutes.clamp(1, 59)}m';
  }
}

class DeleteRoomDialog extends StatelessWidget {
  const DeleteRoomDialog({super.key, required this.roomName, this.isLive = true});

  final String roomName;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Row(
          spacing: 13,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: PTColors.dangerBorder.withValues(alpha: 0.12),
                border: Border.all(color: PTColors.dangerBorder.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(PTRadius.panel),
              ),
              child: const Icon(BoothIcons.delete, size: 24, fill: 1, color: PTColors.danger),
            ),
            Expanded(child: Text('Delete this room?', style: PTText.cardHeading)),
          ],
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: roomName,
                style: TextStyle(color: PTColors.white(0.85)),
              ),
              TextSpan(
                text: isLive
                    ? ' goes for good. Anyone still watching gets sent back to their '
                          "lobby right away. There's no undo."
                    : " goes for good. There's no undo.",
              ),
            ],
          ),
          style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.6), height: 1.55),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            spacing: 11,
            children: [
              Expanded(
                child: PTButton(
                  label: 'Keep it',
                  variant: .secondary,
                  height: 48,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              Expanded(
                child: PTButton(
                  label: 'Delete',
                  variant: .destructive,
                  height: 48,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClearEndedButton extends StatefulWidget {
  const _ClearEndedButton({
    required this.count,
    required this.compact,
    required this.busy,
    required this.onPressed,
  });

  final int count;
  final bool compact;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  State<_ClearEndedButton> createState() => _ClearEndedButtonState();
}

class _ClearEndedButtonState extends State<_ClearEndedButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.busy) {
      return const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: PTLoader(size: 16));
    }

    final tooltip = 'Clear ended rooms (${widget.count})';

    if (widget.compact) {
      return PTIconButton(
        icon: BoothIcons.delete,
        size: 32,
        iconSize: 18,
        glass: false,
        tooltip: tooltip,
        onPressed: widget.onPressed,
      );
    }

    final enabled = widget.onPressed != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: tooltip,
        child: PTPressable(
          enabled: enabled,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: PTColors.white(_hovered ? 0.1 : 0.05),
              border: Border.all(color: PTColors.white(_hovered ? 0.18 : 0.1)),
              borderRadius: BorderRadius.circular(PTRadius.control),
            ),
            child: Row(
              mainAxisSize: .min,
              spacing: 6,
              children: [
                PTOpticalIcon(
                  BoothIcons.delete,
                  beside: PTText.mono.copyWith(fontSize: 12),
                  size: 16,
                  color: PTColors.white(_hovered ? 0.9 : 0.65),
                ),
                Text(
                  'Clear ended',
                  style: PTText.mono.copyWith(
                    fontSize: 12,
                    color: PTColors.white(_hovered ? 0.95 : 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ClearEndedRoomsDialog extends StatelessWidget {
  const ClearEndedRoomsDialog({super.key, required this.count, this.hasPersistentRooms = false});

  final int count;
  final bool hasPersistentRooms;

  @override
  Widget build(BuildContext context) {
    final roomLabel = count == 1 ? 'room' : 'rooms';

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Row(
          spacing: 13,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: PTColors.dangerBorder.withValues(alpha: 0.12),
                border: Border.all(color: PTColors.dangerBorder.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(PTRadius.panel),
              ),
              child: const Icon(BoothIcons.delete, size: 24, fill: 1, color: PTColors.danger),
            ),
            Expanded(child: Text('Clear $count ended $roomLabel?', style: PTText.cardHeading)),
          ],
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text:
                    'This will permanently delete $count ended $roomLabel from your lobby '
                    'and free up room space. There is no undo.',
              ),
              if (hasPersistentRooms) ...[
                const TextSpan(text: '\n\n'),
                TextSpan(
                  text: 'Your saved persistent rooms will stay safe and untouched.',
                  style: TextStyle(color: PTColors.textAccent, fontWeight: .w500),
                ),
              ],
            ],
          ),
          style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.6), height: 1.55),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            spacing: 11,
            children: [
              Expanded(
                child: PTButton(
                  label: 'Keep them',
                  variant: .secondary,
                  height: 48,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              Expanded(
                child: PTButton(
                  label: 'Clear $count $roomLabel',
                  variant: .destructive,
                  height: 48,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
