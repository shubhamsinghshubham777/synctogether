import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/logo.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProfileService.instance,
      builder: (context, _) {
        final profile = ProfileService.instance.profile;
        final reason =
            profile?.banReason ??
            'This account was permanently suspended for violating SyncTogether anti-piracy policies or community guidelines.';

        return Scaffold(
          backgroundColor: PTColors.canvas,
          body: AmbientBackground(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: GlassPanel(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: .min,
                      children: [
                        const PTWordmark(size: 26),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: PTColors.danger.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: PTColors.danger.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(
                            Symbols.block_rounded,
                            size: 44,
                            color: PTColors.danger,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Account Suspended',
                          style: PTText.display.copyWith(
                            fontSize: 22,
                            fontWeight: .bold,
                            color: PTColors.fg,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Your access to SyncTogether rooms, media sharing, and watch parties has been terminated indefinitely.',
                          style: PTText.body.copyWith(color: PTColors.fgMute, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: PTColors.aisle,
                            borderRadius: BorderRadius.circular(PTRadius.control),
                            border: Border.all(color: PTColors.rail),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SUSPENSION REASON',
                                style: PTText.label.copyWith(fontSize: 10, color: PTColors.fgMute),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                reason,
                                style: PTText.body.copyWith(fontSize: 13, color: PTColors.fg),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'SyncTogether does not tolerate unauthorized distribution or playback of copyrighted material. If you believe this action was taken in error, you may file an appeal.',
                          style: PTText.finePrint.copyWith(color: PTColors.fgMute),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        PTButtonBar(
                          buttons: [
                            PTButton(
                              label: 'Contact Support',
                              icon: Symbols.mail_rounded,
                              variant: .secondary,
                              onPressed: () {
                                final uri = Uri(
                                  scheme: 'mailto',
                                  path: 'support@synctogether.app',
                                  queryParameters: {
                                    'subject': 'Account Appeal: ${profile?.id ?? "Suspended User"}',
                                    'body':
                                        'User ID: ${profile?.id ?? ""}\nEmail: ${profile?.email ?? ""}\n\nAppeal details:\n',
                                  },
                                );
                                launchUrl(uri, mode: LaunchMode.externalApplication);
                              },
                            ),
                            PTButton(
                              label: 'Sign Out',
                              icon: BoothIcons.logout,
                              variant: .primary,
                              onPressed: () => AuthService.instance.signOut(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
