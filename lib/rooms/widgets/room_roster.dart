import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/rolling_text.dart';
import 'package:synctogether/ui/reveal.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

import '../roster_fold.dart';

/// One avatar in the chat panel's "In the room" roster.
class ChatRosterSeat {
  const ChatRosterSeat({
    required this.member,
    required this.ready,
    this.premium = false,
    this.frame,
  });

  final PresentMember member;
  final bool ready;
  final bool premium;
  final AvatarFrame? frame;
}

/// "IN THE ROOM · 4" as the roster's kicker.
TextStyle get _kickerStyle =>
    PTText.label.copyWith(letterSpacing: 11 * 0.14, color: PTColors.fgMute);

/// The seats as one line that scrolls sideways rather than wrapping: a
/// sixteen-seat room must not eat the chat's height. Each ring is Cue once the
/// member clears the gate.
class RosterRings extends StatelessWidget {
  const RosterRings({super.key, required this.seats});

  final List<ChatRosterSeat> seats;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: .horizontal,
        padding: EdgeInsets.zero,
        itemCount: seats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final seat = seats[i];
          final m = seat.member;
          return Tooltip(
            message: [
              m.displayName,
              if (m.isHost) 'host',
              seat.ready ? 'ready' : 'getting ready',
            ].join(' · '),
            child: Center(
              child: ReadyRing(
                diameter: 36,
                ready: seat.ready,
                premium: seat.premium,
                clip: false,
                child: PTAvatar(
                  userId: m.userId,
                  displayName: m.displayName,
                  avatarUrl: m.avatarUrl,
                  size: 36,
                  premium: seat.premium,
                  frame: seat.frame,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The phone room's roster: a 44 px toggle row over the rings, which fold away
/// (height only, [PTMotion.panel]) when [fold] says so. Folded, the row keeps
/// the label and shows a stack of the first few rings - the people not yet
/// ready first, so they are never the ones hidden behind "+N" - with an
/// attention dot while anyone is still getting ready.
class FoldableRoster extends StatelessWidget {
  const FoldableRoster({super.key, required this.seats, required this.fold});

  final List<ChatRosterSeat> seats;
  final RosterFold fold;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: fold,
      builder: (context, _) =>
          _FoldedRoster(seats: seats, collapsed: fold.collapsed, onToggle: fold.toggle),
    );
  }
}

/// Ring diameter, ring + gap + stroke, and how far each ring sits over the last.
const double _kMiniDiameter = 20;
const double _kMiniOuter = _kMiniDiameter + 2 * (1.5 + 1.5);
const double _kMiniStep = 18;

/// How many rings (at most five) fit in [room], leaving space for "+N" when
/// someone is cut. Zero when not even one fits.
int miniRingsThatFit({required double room, required int seats, required double plusWidth}) {
  for (var k = math.min(5, seats); k > 0; k--) {
    final width = _kMiniOuter + (k - 1) * _kMiniStep + (seats > k ? 6 + plusWidth : 0);
    if (width <= room) return k;
  }
  return 0;
}

class _FoldedRoster extends StatelessWidget {
  const _FoldedRoster({required this.seats, required this.collapsed, required this.onToggle});

  final List<ChatRosterSeat> seats;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ready = seats.where((s) => s.ready).length;
    final waiting = seats.length - ready;
    final people = seats.length == 1 ? 'person' : 'people';
    final scaler = MediaQuery.textScalerOf(context);
    // Not-ready first: the ones the room is waiting on stay on show.
    final ordered = [...seats.where((s) => !s.ready), ...seats.where((s) => s.ready)];

    return TweenAnimationBuilder<double>(
      tween: Tween(end: collapsed ? 0.0 : 1.0),
      duration: PTMotion.functional(context, PTMotion.panel),
      curve: PTMotion.emphasized,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: RosterRings(seats: seats),
      ),
      builder: (context, t, rings) => DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PTColors.aisle)),
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Semantics(
              container: true,
              button: true,
              expanded: !collapsed,
              excludeSemantics: true,
              label: '${seats.length} $people in the room, $ready ready',
              hint: collapsed ? 'Show everyone' : 'Hide the list',
              onTap: onToggle,
              child: PTPressable(
                onTap: onToggle,
                pressedScale: 0.99,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        // What the label and the chevron take; the stack gets the rest.
                        final label = scaler.scale(124);
                        final room = box.maxWidth - label - 18 - 16 - (waiting > 0 ? 16 : 0);
                        final shown = miniRingsThatFit(
                          room: room,
                          seats: seats.length,
                          plusWidth: scaler.scale(22),
                        );
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                'IN THE ROOM · ${seats.length}',
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: _kickerStyle,
                              ),
                            ),
                            // Folds in as the rings fold out; out of layout once open.
                            ClipRect(
                              child: Align(
                                alignment: .centerRight,
                                widthFactor: 1 - t,
                                child: Opacity(
                                  opacity: 1 - t,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: _MiniStack(
                                      seats: ordered,
                                      shown: shown,
                                      waiting: waiting > 0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Transform.rotate(
                              angle: math.pi * t,
                              child: const Icon(
                                BoothIcons.chevronDown,
                                size: 18,
                                color: PTColors.fgMute,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            ExcludeFocus(
              excluding: t < 0.01,
              child: ExcludeSemantics(
                excluding: t < 0.01,
                child: ClipRect(
                  child: Align(alignment: .topCenter, heightFactor: t, child: rings),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The folded row's rings, overlapped and each still its own ready/waiting
/// colour, with the attention dot ahead of them while anyone is not ready.
class _MiniStack extends StatelessWidget {
  const _MiniStack({required this.seats, required this.shown, required this.waiting});

  final List<ChatRosterSeat> seats;
  final int shown;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final more = seats.length - shown;
    return Row(
      mainAxisSize: .min,
      children: [
        // The waiting dot unfolds in when someone is still to be ready, and folds away
        // when they are.
        PTRevealKeep(
          visible: waiting,
          axis: Axis.horizontal,
          alignment: Alignment.centerLeft,
          child: Container(
            width: 8,
            height: 8,
            margin: EdgeInsets.only(right: shown > 0 ? 8 : 0),
            decoration: const BoxDecoration(shape: .circle, color: PTColors.textAccent),
          ),
        ),
        if (shown > 0)
          SizedBox(
            height: _kMiniOuter,
            child: Row(
              mainAxisSize: .min,
              children: [
                for (var i = 0; i < shown; i++)
                  Align(
                    alignment: .centerLeft,
                    widthFactor: i == shown - 1 ? 1 : _kMiniStep / _kMiniOuter,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(shape: .circle, color: PTColors.canvas),
                      child: ReadyRing(
                        diameter: _kMiniDiameter,
                        gap: 1.5,
                        width: 1.5,
                        ready: seats[i].ready,
                        premium: seats[i].premium,
                        clip: false,
                        child: PTAvatar(
                          userId: seats[i].member.userId,
                          displayName: seats[i].member.displayName,
                          avatarUrl: seats[i].member.avatarUrl,
                          size: _kMiniDiameter,
                        ),
                      ),
                    ),
                  ),
                // "+N" unfolds when the stack overflows, and the number rolls as people
                // come and go.
                PTRevealKeep(
                  visible: more > 0,
                  axis: Axis.horizontal,
                  alignment: Alignment.centerLeft,
                  gap: 6,
                  child: PTRollingText(
                    '+$more',
                    style: PTText.label.copyWith(fontSize: 10, color: PTColors.fgMute),
                    dir: 1,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
