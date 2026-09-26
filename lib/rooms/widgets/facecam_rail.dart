import 'dart:async';
import '../../ui/booth_icons.g.dart';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/av/livekit_service.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

import '../../rewards/rewards_models.dart';

const bool kDemoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);

enum FacecamLayout { railLeft, stripTop, miniStackRight }

/// Facecam tiles per present member: live video when the member publishes a
/// cam track, avatar tile otherwise; self first with a brighter hairline, Signal ring while speaking.
///
/// People arriving and leaving is a social event, so tiles animate both ways:
/// departures are held in the tree for one [PTMotion.state] while they fade,
/// which is why this is stateful.
class FacecamRail extends StatefulWidget {
  const FacecamRail({
    super.key,
    required this.av,
    required this.present,
    required this.selfId,
    required this.layout,
    this.onHide,
    this.maxTiles = 4,
    this.showNames = true,
    this.premiumMembers = const {},
    this.memberFrames = const {},
  });

  final LiveKitService av;
  final List<PresentMember> present;
  final String selfId;
  final FacecamLayout layout;
  final VoidCallback? onHide;
  final int maxTiles;
  final bool showNames;
  final Set<String> premiumMembers;
  final Map<String, AvatarFrame> memberFrames;

  @override
  State<FacecamRail> createState() => _FacecamRailState();
}

class _FacecamRailState extends State<FacecamRail> {
  /// Members that have gone but are still fading out, in their last known
  /// slot order so the rail doesn't reshuffle while they leave.
  final _leaving = <String, PresentMember>{};
  final _leavingTimers = <String, Timer>{};

  List<PresentMember> get _ordered => [
    ...widget.present.where((m) => m.userId == widget.selfId),
    ...widget.present.where((m) => m.userId != widget.selfId),
  ];

  @override
  void didUpdateWidget(FacecamRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = widget.present.map((m) => m.userId).toSet();
    for (final member in oldWidget.present) {
      if (now.contains(member.userId) || _leaving.containsKey(member.userId)) {
        continue;
      }
      _leaving[member.userId] = member;
      _leavingTimers[member.userId] = Timer(PTMotion.state, () {
        _leavingTimers.remove(member.userId);
        if (mounted) setState(() => _leaving.remove(member.userId));
      });
    }
    // A member who reappears mid-fade takes their real slot straight back.
    for (final id in now) {
      _leavingTimers.remove(id)?.cancel();
      _leaving.remove(id);
    }
  }

  @override
  void dispose() {
    for (final timer in _leavingTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.av,
      builder: (context, _) {
        final ordered = _ordered;
        final visible = ordered.take(widget.maxTiles).toList();
        final overflow = ordered.length - visible.length;
        // Leavers only fill slots the live roster isn't using.
        final departing = _leaving.values
            .take((widget.maxTiles - visible.length).clamp(0, widget.maxTiles))
            .toList();

        final tiles = <Widget>[
          for (final member in [...visible, ...departing])
            _AnimatedTile(
              key: ValueKey(member.userId),
              leaving: _leaving.containsKey(member.userId),
              child: _FacecamTile(
                member: member,
                isSelf: member.userId == widget.selfId,
                premium: widget.premiumMembers.contains(member.userId),
                frame: widget.memberFrames[member.userId],
                av: widget.av,
                compact: widget.layout != .railLeft,
                showNames: widget.showNames,
              ),
            ),
          if (overflow > 0 && widget.layout == .miniStackRight)
            PTActionPill(label: '+$overflow', icon: Symbols.sync_rounded),
          if (widget.onHide != null && widget.layout == .railLeft)
            PTActionPill(label: 'Hide cams', icon: BoothIcons.chevronLeft, onTap: widget.onHide),
        ];

        final rail = switch (widget.layout) {
          // Scrolls rather than overflowing when a short (or keyboard-squeezed)
          // window can't fit every tile; inside an unbounded slot it is inert.
          .railLeft => SizedBox(
            width: 200,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: .start, spacing: 10, children: tiles),
            ),
          ),
          .stripTop => Row(spacing: 8, children: [for (final t in tiles) Expanded(child: t)]),
          .miniStackRight => SingleChildScrollView(
            child: Column(crossAxisAlignment: .end, spacing: 6, children: tiles),
          ),
        };

        return AnimatedSize(
          duration: PTMotion.functional(context, PTMotion.state),
          curve: PTMotion.enter,
          alignment: widget.layout == .miniStackRight ? .topRight : .topLeft,
          child: rail,
        );
      },
    );
  }
}

class _AnimatedTile extends StatelessWidget {
  const _AnimatedTile({super.key, required this.child, required this.leaving});

  final Widget child;
  final bool leaving;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: leaving ? 0.95 : 1,
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.exit,
      child: AnimatedOpacity(
        opacity: leaving ? 0 : 1,
        duration: PTMotion.functional(context, PTMotion.state),
        child: PTEntrance(duration: PTMotion.state, offset: 0, scaleFrom: 0.95, child: child),
      ),
    );
  }
}

class _FacecamTile extends StatelessWidget {
  const _FacecamTile({
    required this.member,
    required this.isSelf,
    required this.premium,
    this.frame,
    required this.av,
    required this.compact,
    required this.showNames,
  });

  final PresentMember member;
  final bool isSelf;
  final bool premium;
  final AvatarFrame? frame;
  final LiveKitService av;
  final bool compact;
  final bool showNames;

  lk.Participant? get _participant {
    if (isSelf) return av.localParticipant;
    for (final p in av.remoteParticipants) {
      if (p.identity == member.userId) return p;
    }
    return null;
  }

  static String? _mockFacecamAsset(String userId) {
    switch (userId) {
      case 'user-alex':
        return 'assets/store/facecam_alex.jpg';
      case 'user-sarah':
        return 'assets/store/facecam_sarah.jpg';
      case 'user-david':
        return 'assets/store/facecam_david.jpg';
      case 'user-elena':
        return 'assets/store/facecam_elena.jpg';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final participant = _participant;
    final videoTrack = _videoTrack(participant);
    final isMockOrDemo = kDemoMode || LiveKitService.isMockMode;
    final mockAsset = isMockOrDemo ? _mockFacecamAsset(member.userId) : null;
    final hasVideo = videoTrack != null || mockAsset != null;
    final micOff = _micOff(participant);
    final speaking = participant?.isSpeaking ?? (isMockOrDemo && member.userId == 'user-sarah');

    final height = compact ? 58.0 : 112.0;
    const radius = PTRadius.control;

    // The highest-value AV micro: this is how you know who just laughed. A
    // Signal ring, the colour of a live mic - snaps on and lingers on the way
    // out, the way a voice does. No blurred shadows: these tiles sit over
    // playing video, where every soft shadow is a per-frame cost.
    return AnimatedContainer(
      duration: speaking ? const Duration(milliseconds: 200) : const Duration(milliseconds: 600),
      curve: PTMotion.enter,
      height: height,
      decoration: BoxDecoration(
        color: PTColors.aisle,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: speaking
              ? PTColors.ember
              : isSelf
              ? PTColors.white(0.32)
              : PTColors.rail,
          width: speaking ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - (speaking ? 2 : 1)),
        child: Stack(
          fit: .expand,
          children: [
            if (videoTrack != null)
              lk.VideoTrackRenderer(videoTrack, fit: .cover)
            else if (mockAsset != null)
              Image.asset(mockAsset, fit: BoxFit.cover)
            else
              Center(
                child: Padding(
                  // Clear of the name tag below it.
                  padding: EdgeInsets.only(bottom: compact ? 0 : 14),
                  child: PTAvatar(
                    userId: member.userId,
                    displayName: member.displayName,
                    size: compact ? 24 : 40,
                    premium: premium,
                    frame: frame,
                  ),
                ),
              ),
            Positioned(
              left: compact ? 5 : 8,
              right: compact ? 5 : 8,
              bottom: compact ? 5 : 8,
              // Hugs its name, ellipsizing only once it reaches the far edge.
              child: Row(
                children: [
                  Flexible(
                    child: AnimatedSlide(
                      offset: showNames ? Offset.zero : const Offset(0, 0.5),
                      duration: PTMotion.functional(context, PTMotion.state),
                      curve: showNames ? PTMotion.enter : PTMotion.exit,
                      child: AnimatedOpacity(
                        opacity: showNames ? 1 : 0,
                        duration: PTMotion.functional(context, PTMotion.state),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 7 : 9,
                            vertical: compact ? 2 : 3,
                          ),
                          decoration: BoxDecoration(
                            color: PTColors.canvasScrim,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Row(
                            mainAxisSize: .min,
                            spacing: 3,
                            children: [
                              if (premium)
                                Icon(
                                  BoothIcons.crown,
                                  size: compact ? 10 : 12,
                                  fill: 1,
                                  color: PTColors.premium,
                                ),
                              Flexible(
                                child: Text(
                                  member.displayName,
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: TextStyle(
                                    fontFamily: PTFonts.body,
                                    fontSize: compact ? 9.5 : 12,
                                    fontWeight: .w600,
                                    color: PTColors.fg,
                                  ),
                                ),
                              ),
                              if (!hasVideo && !compact)
                                Icon(
                                  member.privacyMode
                                      ? BoothIcons.visibilityOff
                                      : BoothIcons.videocamOff,
                                  size: 12,
                                  fill: 1,
                                  color: PTColors.white(0.5),
                                )
                              else if (member.privacyMode)
                                Icon(
                                  BoothIcons.visibilityOff,
                                  size: compact ? 10 : 12,
                                  fill: 1,
                                  color: PTColors.white(0.75),
                                ),
                              // The border glow is now the primary speaking cue; this
                              // stays as a redundant, colour-blind-safe marker.
                              AnimatedSize(
                                duration: PTMotion.functional(context, PTMotion.state),
                                curve: PTMotion.enter,
                                child: speaking
                                    ? Icon(
                                        Symbols.graphic_eq_rounded,
                                        size: compact ? 10 : 12,
                                        color: PTColors.ember,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: compact ? 5 : 7,
              right: compact ? 5 : 7,
              child: AnimatedScale(
                scale:
                    (micOff && participant != null) ||
                        (isMockOrDemo && member.userId == 'user-david')
                    ? 1
                    : 0,
                duration: PTMotion.functional(context, PTMotion.state),
                curve: micOff ? PTMotion.arrive : PTMotion.exit,
                child: Container(
                  width: compact ? 17 : 22,
                  height: compact ? 17 : 22,
                  decoration: BoxDecoration(
                    color: PTColors.dangerSurface,
                    shape: .circle,
                    border: Border.all(color: PTColors.dangerBorder.withValues(alpha: 0.45)),
                  ),
                  child: Icon(
                    BoothIcons.micOff,
                    size: compact ? 10 : 12,
                    fill: 1,
                    color: PTColors.danger,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _micOff(lk.Participant? participant) {
    if (participant == null) return true;
    final pubs = participant.audioTrackPublications;
    return pubs.isEmpty || pubs.every((pub) => pub.muted);
  }

  lk.VideoTrack? _videoTrack(lk.Participant? participant) {
    if (participant == null) return null;
    for (final publication in participant.videoTrackPublications) {
      if (publication.subscribed && !publication.muted && publication.track != null) {
        return publication.track as lk.VideoTrack;
      }
    }
    return null;
  }
}
