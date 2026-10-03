import 'dart:async';

import 'package:flutter/material.dart';
import 'package:synctogether/av/video_trial.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// "VIDEO TRIAL · 9:42" above the facecams (board 32). Beam while it runs,
/// Signal in the last minute - no sound, no pulse. Ticks once a second on its
/// own so the rail around it never rebuilds for the clock.
class VideoTrialChip extends StatefulWidget {
  const VideoTrialChip({
    super.key,
    required this.endsAt,
    required this.now,
    this.compact = false,
    this.short = false,
  });

  final DateTime endsAt;

  /// The server-corrected clock (`RoomService.serverNow`), so every member's
  /// countdown agrees with the server's cutoff rather than their own clock.
  final DateTime Function() now;

  /// The phone strip and the landscape mini stack: smaller, one line.
  final bool compact;

  /// "TRIAL 6:15", for the landscape mini stack where every pixel is video.
  final bool short;

  @override
  State<VideoTrialChip> createState() => _VideoTrialChipState();
}

class _VideoTrialChipState extends State<VideoTrialChip> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.endsAt.difference(widget.now());
    final last = left <= kVideoTrialFinalStretch;
    final ink = last ? PTColors.danger : PTColors.fgDim;
    final dot = last ? PTColors.dangerBorder : PTColors.primary;
    final style = PTText.label.copyWith(
      fontSize: widget.compact ? 10 : 11,
      letterSpacing: 1.1,
      color: ink,
    );
    final time = Text(
      videoTrialCountdown(left),
      style: style.copyWith(fontWeight: .w600, color: last ? PTColors.danger : PTColors.fg),
    );
    return Semantics(
      liveRegion: false,
      label: 'Video trial, ${videoTrialCountdown(left)} left',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: PTMotion.functional(context, PTMotion.state),
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 8 : 10,
          vertical: widget.compact ? 4 : 7,
        ),
        decoration: BoxDecoration(
          color: PTColors.glassBase,
          borderRadius: BorderRadius.circular(PTRadius.control),
          border: Border.all(color: last ? PTColors.dangerBorder : PTColors.rail),
        ),
        child: Row(
          mainAxisSize: widget.compact ? .min : .max,
          spacing: widget.compact ? 6 : 8,
          children: [
            Container(
              width: widget.compact ? 6 : 7,
              height: widget.compact ? 6 : 7,
              decoration: BoxDecoration(color: dot, shape: .circle),
            ),
            Flexible(
              fit: widget.compact ? .loose : .tight,
              child: Text(
                widget.short ? 'TRIAL' : 'VIDEO TRIAL',
                maxLines: 1,
                overflow: .ellipsis,
                style: style,
              ),
            ),
            time,
          ],
        ),
      ),
    );
  }
}

/// "Faces off, voice still on". The host gets the one thing they can act on;
/// members get the reason and nothing to press.
class VideoTrialEndedNote extends StatelessWidget {
  const VideoTrialEndedNote({super.key, this.onKeepFaces, this.compact = false});

  /// Host only. Null renders the member variant.
  final VoidCallback? onKeepFaces;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PTEntrance(
      duration: PTMotion.state,
      offset: 0,
      scaleFrom: 0.95,
      child: GlassPanel(
        radius: PTRadius.control,
        padding: EdgeInsets.all(compact ? 8 : 12),
        child: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          spacing: compact ? 6 : 8,
          children: [
            Row(
              crossAxisAlignment: .start,
              spacing: 8,
              children: [
                Icon(BoothIcons.videocamOff, size: compact ? 14 : 16, color: PTColors.fgDim),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    mainAxisSize: .min,
                    spacing: 3,
                    children: [
                      Text(
                        'Faces off, voice still on',
                        maxLines: 2,
                        overflow: .ellipsis,
                        style: PTText.finePrint.copyWith(
                          fontSize: compact ? 11 : 12,
                          fontWeight: .w700,
                          color: PTColors.fg,
                        ),
                      ),
                      if (!compact)
                        Text(
                          onKeepFaces != null
                              ? 'Patron rooms keep video on all night, for everyone in them.'
                              : "That was this room's video trial.",
                          style: PTText.finePrint.copyWith(fontSize: 11, color: PTColors.fgDim),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (onKeepFaces != null) _KeepFacesButton(onTap: onKeepFaces!),
          ],
        ),
      ),
    );
  }
}

/// Brass outline, the premium button shape on board 32.
class _KeepFacesButton extends StatelessWidget {
  const _KeepFacesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: PTPressable(
          onTap: onTap,
          child: Container(
            height: 32,
            alignment: .center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PTRadius.control),
              border: Border.all(color: PTColors.premiumBorder),
            ),
            child: Text(
              'Keep faces on',
              maxLines: 1,
              overflow: .ellipsis,
              style: PTText.buttonLabel.copyWith(fontSize: 13, color: PTColors.premium),
            ),
          ),
        ),
      ),
    );
  }
}
