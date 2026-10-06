import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Shows the "House lights up" / "Room ended" dialog when a room is completed,
/// evicted, kicked, or deleted.
void showRoomEndedDialog({
  required BuildContext context,
  required ValueListenable<bool> resuming,
  required bool isMobile,
  required String? evictionReason,
  required String title,
  required String body,
  required IconData icon,
  required bool persistent,
  required bool canShowPremiumUpsell,
  required Future<void> Function() onBackToLobby,
  required VoidCallback onPremiumUpsell,
}) {
  showGlassDialog(
    context: context,
    barrierDismissible: false,
    width: isMobile ? 370 : 390,
    // canPop false: Esc/back would otherwise strand the user on a dead room
    // screen with no way to re-show this dialog.
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: ValueListenableBuilder<bool>(
        valueListenable: resuming,
        builder: (dialogContext, isResuming, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The end of a show is pressed onto the ticket, once: an ink
            // stamp, not a glow that breathes for as long as the dialog is up.
            PTStamp(
              size: 104,
              angle: -0.16,
              color: evictionReason == 'kicked' || evictionReason == 'deleted'
                  ? PTColors.ember
                  : PTColors.primary,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 26, fill: 1),
                  const SizedBox(height: 4),
                  Text(
                    persistent ? 'SAVED' : 'FIN',
                    style: const TextStyle(
                      fontFamily: PTFonts.display,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: 1,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            PTEntrance(
              delay: const Duration(milliseconds: 60),
              duration: PTMotion.state,
              offset: 8,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: PTText.display.copyWith(fontSize: 30, letterSpacing: -0.8),
              ),
            ),
            const SizedBox(height: 10),
            PTEntrance(
              delay: const Duration(milliseconds: 100),
              duration: PTMotion.state,
              offset: 8,
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.6), height: 1.5),
              ),
            ),
            const SizedBox(height: 24),
            PTEntrance(
              delay: const Duration(milliseconds: 140),
              duration: PTMotion.state,
              offset: 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  PTButton(
                    label: 'Back to the lobby',
                    variant: .primary,
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      await onBackToLobby();
                    },
                  ),
                  if (canShowPremiumUpsell)
                    PTButton(
                      label: 'Unlock 24h rooms with Premium',
                      icon: BoothIcons.crown,
                      variant: .secondary,
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        onPremiumUpsell();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
