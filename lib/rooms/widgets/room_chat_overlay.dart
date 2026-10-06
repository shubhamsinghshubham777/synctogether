import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:synctogether/rewards/rewards_models.dart';
import 'package:synctogether/sync/sync_logic.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Floating stack of the last few incoming messages, shown while the chat
/// panel is closed (desktop/landscape). Bottom-aligned so new bubbles push up.
class RoomChatOverlay extends StatelessWidget {
  const RoomChatOverlay({
    required this.messages,
    required this.expiringMessages,
    required this.premiumMembers,
    required this.memberFrames,
    required this.onTapMessage,
    super.key,
  });

  final List<ChatMessage> messages;
  final Set<ChatMessage> expiringMessages;
  final Set<String> premiumMembers;
  final Map<String, AvatarFrame> memberFrames;
  final VoidCallback onTapMessage;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      alignment: .bottomLeft,
      child: Column(
        mainAxisSize: .min,
        mainAxisAlignment: .end,
        crossAxisAlignment: .start,
        children: [
          for (final message in messages)
            Padding(
              key: ValueKey(message),
              padding: const EdgeInsets.only(top: 8),
              child: AnimatedSlide(
                offset: expiringMessages.contains(message) ? const Offset(-0.12, 0) : Offset.zero,
                duration: PTMotion.functional(context, PTMotion.state),
                curve: PTMotion.exit,
                child: AnimatedOpacity(
                  opacity: expiringMessages.contains(message) ? 0 : 1,
                  duration: PTMotion.functional(context, PTMotion.state),
                  child: PTEntrance(
                    duration: PTMotion.panel,
                    offset: 8,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: .opaque,
                        onTap: onTapMessage,
                        child: _OverlayBubbleBody(
                          message: message,
                          isPremium: premiumMembers.contains(message.senderId),
                          frame: memberFrames[message.senderId],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverlayBubbleBody extends StatelessWidget {
  const _OverlayBubbleBody({required this.message, required this.isPremium, required this.frame});

  final ChatMessage message;
  final bool isPremium;
  final AvatarFrame? frame;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      crossAxisAlignment: .end,
      spacing: 8,
      children: [
        PTAvatar(
          userId: message.senderId,
          displayName: message.displayName,
          size: 26,
          premium: isPremium,
          frame: frame,
        ),
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: math.min(260, MediaQuery.sizeOf(context).width * 0.7),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: PTColors.surfaceBase.withValues(alpha: 0.74),
              border: Border.all(color: PTColors.white(0.1)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(PTRadius.panel),
                topRight: Radius.circular(PTRadius.panel),
                bottomRight: Radius.circular(PTRadius.panel),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(
                  message.displayName,
                  style: const TextStyle(
                    fontFamily: PTFonts.body,
                    fontSize: 11,
                    fontWeight: .w600,
                    color: PTColors.textAccent,
                  ),
                ),
                Text(message.content, style: PTText.body.copyWith(fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The chat panel itself: slides in from off the right edge and unmounts at rest.
class RoomChatRevealed extends StatelessWidget {
  const RoomChatRevealed({
    required this.animation,
    required this.offscreen,
    required this.panel,
    super.key,
  });

  final Animation<double> animation;
  final double offscreen;
  final Widget panel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: panel,
      builder: (_, child) {
        final t = animation.value;
        // IgnorePointer even when empty: a Positioned parent hands down tight
        // constraints, so a bare SizedBox still fills (and blocks) the slot.
        if (t == 0) return const IgnorePointer(child: SizedBox.shrink());
        return IgnorePointer(
          ignoring: animation.status == AnimationStatus.reverse,
          child: Transform.translate(offset: Offset((1 - t) * offscreen, 0), child: child),
        );
      },
    );
  }
}

/// Chrome the open panel takes the place of: cross-fades out against the panel's arrival.
class RoomChatDisplaced extends StatelessWidget {
  const RoomChatDisplaced({required this.animation, required this.displaced, super.key});

  final Animation<double> animation;
  final Widget displaced;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: displaced,
      builder: (_, child) {
        final t = animation.value;
        if (t == 1) return const SizedBox.shrink();
        return IgnorePointer(
          ignoring: t > 0,
          child: Opacity(opacity: (1 - t).clamp(0.0, 1.0), child: child),
        );
      },
    );
  }
}
