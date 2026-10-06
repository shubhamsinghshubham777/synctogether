import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Floating glass pill displaying room title, code chip, sync status, and time countdown.
class RoomPill extends StatelessWidget {
  const RoomPill({
    required this.room,
    required this.compact,
    required this.syncDotState,
    required this.isHost,
    required this.timeLeft,
    required this.countdownLabel,
    required this.onCopyCode,
    this.onExtendRoom,
    this.isExtending = false,
    this.isYouTube = false,
    this.isAdPlaying = false,
    this.onDebugToggleAd,
    super.key,
  });

  final Room room;
  final bool compact;
  final SyncDotState syncDotState;
  final bool isHost;
  final Duration timeLeft;
  final String countdownLabel;
  final VoidCallback onCopyCode;
  final VoidCallback? onExtendRoom;
  final bool isExtending;
  final bool isYouTube;
  final bool isAdPlaying;
  final VoidCallback? onDebugToggleAd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => RoomPillBody(
        room: room,
        compact: compact,
        showCode: !compact || box.maxWidth >= MediaQuery.textScalerOf(context).scale(250),
        syncDotState: syncDotState,
        isHost: isHost,
        timeLeft: timeLeft,
        countdownLabel: countdownLabel,
        onCopyCode: onCopyCode,
        onExtendRoom: onExtendRoom,
        isExtending: isExtending,
        isYouTube: isYouTube,
        isAdPlaying: isAdPlaying,
        onDebugToggleAd: onDebugToggleAd,
      ),
    );
  }
}

/// The inner row of [RoomPill].
class RoomPillBody extends StatelessWidget {
  const RoomPillBody({
    required this.room,
    required this.compact,
    required this.showCode,
    required this.syncDotState,
    required this.isHost,
    required this.timeLeft,
    required this.countdownLabel,
    required this.onCopyCode,
    this.onExtendRoom,
    this.isExtending = false,
    this.isYouTube = false,
    this.isAdPlaying = false,
    this.onDebugToggleAd,
    super.key,
  });

  final Room room;
  final bool compact;
  final bool showCode;
  final SyncDotState syncDotState;
  final bool isHost;
  final Duration timeLeft;
  final String countdownLabel;
  final VoidCallback onCopyCode;
  final VoidCallback? onExtendRoom;
  final bool isExtending;
  final bool isYouTube;
  final bool isAdPlaying;
  final VoidCallback? onDebugToggleAd;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: .min,
      spacing: compact ? 12 : 10,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? double.infinity : 200),
            child: Text(
              room.name,
              maxLines: 1,
              overflow: .ellipsis,
              style: compact
                  ? PTText.panelHeading.copyWith(fontSize: 13)
                  : PTText.panelHeading.copyWith(fontSize: 14, fontWeight: .w700),
            ),
          ),
        ),
        if (showCode)
          RoomCodeChip(code: room.code, onCopy: onCopyCode, fontSize: 11, plain: !compact),
        Tooltip(
          message: switch (syncDotState) {
            .locked => 'In sync with the room',
            .catchingUp => 'Catching up',
            .reconnecting => 'Reconnecting…',
            .idle => 'Nothing playing together yet',
          },
          child: SyncDot(state: syncDotState, size: 7),
        ),
        if (kDebugMode && isYouTube && onDebugToggleAd != null)
          PTIconButton(
            icon: Symbols.campaign_rounded,
            size: compact ? 26 : 30,
            iconSize: compact ? 15 : 17,
            glass: false,
            tooltip: isAdPlaying
                ? 'Debug: End simulated ad (F2)'
                : 'Debug: Simulate YouTube ad (F2)',
            color: isAdPlaying ? PTColors.notice : null,
            onPressed: onDebugToggleAd,
          ),
        _countdownSlot(
          compact: compact,
          child: Tooltip(
            message: isHost ? 'Extend room duration' : 'Time remaining',
            child: MouseRegion(
              cursor: isHost ? SystemMouseCursors.click : SystemMouseCursors.basic,
              child: GestureDetector(
                onTap: isHost && !isExtending ? onExtendRoom : null,
                child: Row(
                  mainAxisSize: .min,
                  spacing: 6,
                  children: [
                    if (compact)
                      PTPulse(
                        enabled: timeLeft > Duration.zero && timeLeft <= const Duration(minutes: 1),
                        low: 0.35,
                        child: Icon(BoothIcons.schedule, size: 13, color: PTColors.white(0.7)),
                      ),
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: PTMotion.functional(context, PTMotion.state),
                        curve: PTMotion.enter,
                        style: PTText.mono.copyWith(
                          fontSize: 11,
                          color: timeLeft > Duration.zero && timeLeft <= const Duration(minutes: 5)
                              ? PTColors.warning
                              : compact
                              ? PTColors.white(0.7)
                              : PTColors.fgDim,
                        ),
                        child: Text(
                          compact ? countdownLabel.replaceAll(' left', '') : countdownLabel,
                          maxLines: 1,
                          overflow: .ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return GlassPill(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 12),
      child: compact ? row : SizedBox(height: 38, child: row),
    );
  }

  Widget _countdownSlot({required bool compact, required Widget child}) =>
      compact ? child : Flexible(child: child);
}
