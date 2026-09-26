import 'dart:math' as math;
import '../../ui/booth_icons.g.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/widgets/readiness_overlay.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

import '../../rewards/rewards_models.dart';

/// Everything the overflow menu renders, as one snapshot.
///
/// The menu is a Navigator route, so it lives in a sibling subtree of
/// `RoomScreen` and its `setState` can never reach it - the values are pushed
/// through a [ValueListenable] instead. Republished by
/// `_RoomScreenState._publishMenuData` whenever any input changes (presence,
/// membership, role, canonical media, transport lock).
class RoomMenuData {
  const RoomMenuData({
    required this.members,
    required this.present,
    required this.media,
    required this.transportLock,
    required this.selfId,
    required this.selfIsHost,
    this.canAssignHost = false,
    this.premiumMembers = const {},
    this.memberFrames = const {},
    this.blockedIds = const {},
    this.maxMembers,
  });

  static const empty = RoomMenuData(
    members: [],
    present: [],
    media: RoomMedia.none,
    transportLock: false,
    selfId: '',
    selfIsHost: false,
    canAssignHost: false,
  );

  final List<RoomMember> members;
  final List<PresentMember> present;
  final RoomMedia media;
  final bool transportLock;
  final String selfId;
  final bool selfIsHost;
  final bool canAssignHost;
  final Set<String> premiumMembers;
  final Map<String, AvatarFrame> memberFrames;

  /// Who this account has blocked. The member list is the one surface that
  /// still shows them - it is where unblocking lives, so hiding them here
  /// would make a block permanent by accident.
  final Set<String> blockedIds;

  /// The room's seat count (`rooms.max_members`, from the host's tier). The
  /// header reads "N OF max" only when it is known - never a guessed 8.
  final int? maxMembers;

  /// Derived rather than passed alongside, so "who is online" and "who is
  /// ready" can never disagree.
  Set<String> get onlineIds => {for (final m in present) m.userId};

  PresentMember? presenceOf(String userId) => present.where((p) => p.userId == userId).firstOrNull;
}

/// A playback control the room moved out of a crowded control bar (source,
/// file, audio track, subtitles on a narrow phone), listed above the room
/// actions so it stays one tap from the bar's overflow button.
class RoomMenuAction {
  const RoomMenuAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Anchored top-right glass menu: member list (presence + Host badge) and
/// room actions. `Room.dc.html` overflow-menu detail.
///
/// [data] is live: members leaving, readiness chips, host succession and the
/// transport lock all update while the menu is open. A `null` value means the
/// room is over and the menu must close itself.
Future<void> showRoomOverflowMenu({
  required BuildContext context,
  required ValueListenable<RoomMenuData?> data,
  required VoidCallback onCopyInvite,
  required VoidCallback onLeave,
  required VoidCallback onEndRoom,
  VoidCallback? onExtendRoom,
  VoidCallback? onReportConcern,
  required ValueChanged<bool> onTransportLockChanged,
  required void Function(RoomMember member) onKick,
  void Function(RoomMember member)? onAssignHost,
  void Function(RoomMember member)? onReportMember,
  void Function(RoomMember member)? onUnblockMember,
  List<RoomMenuAction> playbackActions = const [],
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'room menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (dialogContext, _, _) {
      // SafeArea ignores the keyboard, so lift the bottom edge above it too:
      // otherwise the last actions sit under an open keyboard.
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(dialogContext).bottom),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: .topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 76, right: 24),
                // Width gives way to the window (300 is wider than a 320 phone
                // less its gutters). Height is whatever the window leaves: a fixed
                // cap cut the last action in half on windows with room to spare.
                // The panel scrolls only when the window is genuinely short.
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(300, MediaQuery.sizeOf(dialogContext).width - 32),
                    maxHeight: math.max(0, constraints.maxHeight - 76 - 16),
                  ),
                  child: Material(
                    type: .transparency,
                    child: _OverflowMenuPanel(
                      data: data,
                      onCopyInvite: onCopyInvite,
                      onLeave: onLeave,
                      onEndRoom: onEndRoom,
                      onExtendRoom: onExtendRoom,
                      onReportConcern: onReportConcern,
                      onTransportLockChanged: onTransportLockChanged,
                      onKick: onKick,
                      onAssignHost: onAssignHost,
                      onReportMember: onReportMember,
                      onUnblockMember: onUnblockMember,
                      playbackActions: playbackActions,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      // Slide + scale, never fade: the menu is a GlassPanel, and an opacity
      // layer over its BackdropFilter blurs an empty layer (the glass trap).
      return SlideTransition(
        position: Tween(begin: const Offset(0, -0.02), end: Offset.zero).animate(curved),
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(curved),
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    },
  );
}

class _OverflowMenuPanel extends StatefulWidget {
  const _OverflowMenuPanel({
    required this.data,
    required this.onCopyInvite,
    required this.onLeave,
    required this.onEndRoom,
    this.onExtendRoom,
    this.onReportConcern,
    this.onReportMember,
    this.onUnblockMember,
    required this.onTransportLockChanged,
    required this.onKick,
    this.onAssignHost,
    this.playbackActions = const [],
  });

  final ValueListenable<RoomMenuData?> data;
  final List<RoomMenuAction> playbackActions;
  final VoidCallback onCopyInvite;
  final VoidCallback onLeave;
  final VoidCallback onEndRoom;
  final VoidCallback? onExtendRoom;
  final VoidCallback? onReportConcern;
  final void Function(RoomMember member)? onReportMember;
  final void Function(RoomMember member)? onUnblockMember;
  final ValueChanged<bool> onTransportLockChanged;
  final void Function(RoomMember member) onKick;
  final void Function(RoomMember member)? onAssignHost;

  @override
  State<_OverflowMenuPanel> createState() => _OverflowMenuPanelState();
}

class _OverflowMenuPanelState extends State<_OverflowMenuPanel> {
  /// Last non-null snapshot: keeps the panel rendered for the frame between
  /// "the room ended" and this route actually going away.
  late RoomMenuData _data = widget.data.value ?? RoomMenuData.empty;

  @override
  void initState() {
    super.initState();
    widget.data.addListener(_onData);
  }

  @override
  void dispose() {
    widget.data.removeListener(_onData);
    super.dispose();
  }

  void _onData() {
    final next = widget.data.value;
    if (next == null) {
      _forceClose();
      return;
    }
    setState(() => _data = next);
  }

  /// Eviction path. Not `Navigator.pop` - that pops whatever is topmost, and
  /// another dialog (the source chooser after inheriting host) may have opened
  /// above us in the meantime.
  void _forceClose() {
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  /// User taps: the menu is topmost by definition here, so pop normally and
  /// keep the exit transition.
  void _dismiss(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final onlineIds = data.onlineIds;
    return GlassPanel(
      baseColor: PTColors.surfaceBase,
      shadow: true,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Text(
                data.maxMembers == null
                    ? 'IN THE ROOM · ${data.members.length}'
                    : 'IN THE ROOM · ${data.members.length} OF ${data.maxMembers}',
                style: PTText.label,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  for (final member in data.members)
                    _MemberRow(
                      premium: data.premiumMembers.contains(member.userId),
                      frame: data.memberFrames[member.userId],
                      key: ValueKey(member.userId),
                      member: member,
                      online: onlineIds.contains(member.userId),
                      isSelf: member.userId == data.selfId,
                      media: data.media,
                      presence: data.presenceOf(member.userId),
                      onKick: data.selfIsHost && member.userId != data.selfId && !member.isHost
                          ? () => _dismiss(() => widget.onKick(member))
                          : null,
                      onAssignHost:
                          (data.canAssignHost || data.selfIsHost) &&
                              member.userId != data.selfId &&
                              !member.isHost &&
                              widget.onAssignHost != null
                          ? () => _dismiss(() => widget.onAssignHost!(member))
                          : null,
                      blocked: data.blockedIds.contains(member.userId),
                      // Reporting is not a host power - anyone can flag
                      // anyone but themselves, which is the whole point.
                      onReport: member.userId != data.selfId && widget.onReportMember != null
                          ? () => _dismiss(() => widget.onReportMember!(member))
                          : null,
                      onUnblock: widget.onUnblockMember != null
                          ? () => _dismiss(() => widget.onUnblockMember!(member))
                          : null,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(height: 1, color: PTColors.rail),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Column(
                children: [
                  for (final action in widget.playbackActions)
                    _ActionRow(
                      icon: action.icon,
                      iconColor: PTColors.white(0.7),
                      label: action.label,
                      onTap: () => _dismiss(action.onTap),
                    ),
                  _ActionRow(
                    icon: BoothIcons.link,
                    iconColor: PTColors.white(0.7),
                    label: 'Copy invite link',
                    onTap: () => _dismiss(widget.onCopyInvite),
                  ),
                  if (data.selfIsHost && widget.onExtendRoom != null)
                    _ActionRow(
                      icon: BoothIcons.schedule,
                      iconColor: PTColors.white(0.7),
                      label: 'Extend room',
                      onTap: () => _dismiss(widget.onExtendRoom!),
                    ),
                  if (data.selfIsHost)
                    _ActionRow(
                      icon: data.transportLock ? BoothIcons.lock : Symbols.lock_open_rounded,
                      iconColor: data.transportLock ? PTColors.warningBorder : PTColors.white(0.7),
                      label: data.transportLock ? 'You have the remote' : 'Take the remote',
                      onTap: () =>
                          _dismiss(() => widget.onTransportLockChanged(!data.transportLock)),
                    ),
                  if (widget.onReportConcern != null)
                    _ActionRow(
                      icon: BoothIcons.flag,
                      iconColor: PTColors.white(0.7),
                      label: 'Report a concern',
                      onTap: () => _dismiss(widget.onReportConcern!),
                    ),
                  _ActionRow(
                    icon: BoothIcons.logout,
                    iconColor: PTColors.white(0.7),
                    label: 'Leave room',
                    onTap: () => _dismiss(widget.onLeave),
                  ),
                  // The one irreversible action, below its own rule, in Signal.
                  if (data.selfIsHost) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Container(height: 1, color: PTColors.rail),
                    ),
                    _ActionRow(
                      icon: BoothIcons.power,
                      iconColor: PTColors.ember,
                      label: 'End for everyone',
                      labelColor: PTColors.ember,
                      onTap: () => _dismiss(widget.onEndRoom),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    super.key,
    required this.member,
    required this.premium,
    this.frame,
    required this.online,
    required this.isSelf,
    required this.media,
    required this.presence,
    required this.onKick,
    this.onAssignHost,
    this.blocked = false,
    this.onReport,
    this.onUnblock,
  });

  final RoomMember member;
  final bool premium;
  final AvatarFrame? frame;
  final bool online;
  final bool isSelf;
  final RoomMedia media;

  /// Readiness rides on presence, so an offline member simply has none.
  final PresentMember? presence;
  final VoidCallback? onKick;
  final VoidCallback? onAssignHost;
  final bool blocked;
  final VoidCallback? onReport;
  final VoidCallback? onUnblock;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: online ? 1 : 0.55,
      duration: PTMotion.functional(context, PTMotion.state),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          spacing: 12,
          children: [
            // Readiness reads off the ring (Cue once they have the room's
            // media open), the same ReadyRing the docked roster uses.
            ReadyRing(
              diameter: 30,
              gap: 1.5,
              clip: false,
              ready: presence != null && media.isSet && memberSatisfiesGate(presence!, media),
              premium: premium,
              child: PTAvatar(
                userId: member.userId,
                displayName: member.displayName,
                avatarUrl: member.profile?.avatarUrl,
                size: 30,
                presence: online,
                premium: premium,
                frame: frame,
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: member.displayName,
                  children: [
                    if (isSelf)
                      TextSpan(
                        text: ' (you)',
                        style: TextStyle(fontWeight: .w400, color: PTColors.white(0.45)),
                      )
                    else if (!online)
                      TextSpan(
                        text: ' · away',
                        style: TextStyle(fontWeight: .w400, color: PTColors.white(0.45)),
                      )
                    else if (presence?.privacyMode ?? false)
                      TextSpan(
                        text: ' · screen hidden',
                        style: TextStyle(fontWeight: .w400, color: PTColors.white(0.45)),
                      ),
                  ],
                ),
                overflow: .ellipsis,
                style: PTText.body.copyWith(fontSize: 14, fontWeight: .w500),
              ),
            ),
            if (blocked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(PTRadius.control),
                  border: Border.all(color: PTColors.rail),
                ),
                child: Text(
                  'Blocked',
                  style: PTText.finePrint.copyWith(fontSize: 11, color: PTColors.white(0.6)),
                ),
              )
            else if (presence != null && media.isSet)
              _chip(context),
            if (member.isHost && !blocked) const DialogTag('Host', tone: DialogTagTone.host),
            if (premium && !blocked) const DialogTag('Patron', tone: DialogTagTone.premium),
            if (onAssignHost != null)
              PTIconButton(
                icon: BoothIcons.star,
                glass: false,
                size: 30,
                iconSize: 16,
                tooltip: 'Make host',
                onPressed: onAssignHost,
              ),
            if (blocked && onUnblock != null)
              PTIconButton(
                icon: Symbols.person_add_rounded,
                glass: false,
                size: 30,
                iconSize: 16,
                tooltip: 'Unblock ${member.displayName}',
                onPressed: onUnblock,
              )
            else if (onReport != null)
              PTIconButton(
                icon: BoothIcons.flag,
                glass: false,
                size: 30,
                iconSize: 16,
                tooltip: 'Report or block ${member.displayName}',
                onPressed: onReport,
              ),
            if (onKick != null)
              PTIconButton(
                icon: BoothIcons.personRemove,
                glass: false,
                size: 30,
                iconSize: 16,
                tooltip: 'Show ${member.displayName} out',
                onPressed: onKick,
              ),
          ],
        ),
      ),
    );
  }

  /// Same treatment as the readiness overlay's chip - the two are read side by
  /// side often enough that they must not behave differently.
  Widget _chip(BuildContext context) {
    final status = ReadinessChipStyle.of(presence!, media);
    return AnimatedContainer(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      // Grows a little with the text size so a scaled label still gets its
      // word in before the ellipsis, but never crowds the name out of the row.
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.textScalerOf(context).scale(116), 150),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PTRadius.control),
        border: Border.all(color: status.color.withValues(alpha: 0.5)),
      ),
      child: AnimatedSwitcher(
        duration: PTMotion.functional(context, PTMotion.state),
        switchInCurve: PTMotion.enter,
        switchOutCurve: PTMotion.exit,
        child: Text(
          status.label,
          key: ValueKey(status.label),
          overflow: .ellipsis,
          style: PTText.finePrint.copyWith(color: status.color, fontWeight: .w500),
        ),
      ),
    );
  }
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.labelColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PTPressable(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: PTMotion.functional(context, PTMotion.hover),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.labelColor == PTColors.ember
                      ? PTColors.dangerBorder.withValues(alpha: 0.1)
                      : PTColors.aisle)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(PTRadius.control),
          ),
          child: Row(
            spacing: 12,
            children: [
              Icon(widget.icon, size: 19, color: widget.iconColor),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: PTText.body.copyWith(fontSize: 14, color: widget.labelColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
