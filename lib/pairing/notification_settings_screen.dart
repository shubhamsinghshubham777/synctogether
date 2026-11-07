import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/banners.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/inputs.dart';
import '../ui/pt_theme.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_widgets.dart';
import 'push_service.dart';

/// Four switches and quiet hours. Only things from your person and your plans;
/// nothing promotional. The system permission is asked for when the first switch
/// is turned on, never before - the moment its reason is obvious.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(PairService.instance.loadPrefs());
    unawaited(PushService.instance.start());
  }

  Future<void> _set(String key, bool value) async {
    final push = PushService.instance;
    // Turning one on is what earns the OS prompt. Turning one off needs none.
    if (value && !push.enabled) {
      final result = await push.enable();
      if (!mounted) return;
      if (result != PushPermission.granted) {
        showPTSnack(
          context,
          result == PushPermission.unsupported
              ? "This device can't receive notifications."
              : 'Notifications are off in your system settings.',
          kind: .info,
        );
        return;
      }
    }
    await PairService.instance.setPref(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([PairService.instance, PushService.instance]),
      builder: (context, _) {
        final prefs = PairService.instance.prefs;
        final push = PushService.instance;
        final partner =
            PairService.instance.pair?.partner.displayName.split(' ').first ?? 'your person';

        return PairPage(
          title: 'Notifications',
          children: [
            Text(
              'Only things from $partner and your plans. Nothing promotional.',
              style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
            ),
            if (!push.supported)
              const PairPanel(
                child: PairNote(
                  "This device can't receive notifications, so these switches have nothing to send to.",
                ),
              )
            else ...[
              if (push.permission == PushPermission.denied)
                PairPanel(
                  brass: false,
                  child: Column(
                    crossAxisAlignment: .stretch,
                    spacing: 12,
                    children: [
                      Text(
                        'Notifications are off for SyncTogether in your system settings.',
                        style: PTText.body.copyWith(
                          fontSize: 14,
                          color: PTColors.warning,
                          height: 1.4,
                        ),
                      ),
                      PTButton(
                        label: 'Open settings',
                        variant: .secondary,
                        icon: BoothIcons.openInNew,
                        height: 42,
                        onPressed: push.openSettings,
                      ),
                    ],
                  ),
                ),
              PairPanel(
                child: Column(
                  spacing: 18,
                  children: [
                    PTToggleRow(
                      title: 'Calls from $partner',
                      subtitle: 'When $partner opens Our Room and rings you.',
                      value: prefs.calls,
                      onChanged: (v) => _set('calls', v),
                    ),
                    PTToggleRow(
                      title: 'Date night reminders',
                      subtitle: 'Fifteen minutes before, and when one is proposed or answered.',
                      value: prefs.dateNights,
                      onChanged: (v) => _set('date_nights', v),
                    ),
                    PTToggleRow(
                      title: 'Watchlist additions',
                      subtitle: 'When $partner adds a title.',
                      value: prefs.watchlist,
                      onChanged: (v) => _set('watchlist', v),
                    ),
                    PTToggleRow(
                      title: 'Reunion countdown',
                      subtitle: 'Every Sunday, and the day before.',
                      value: prefs.reunion,
                      onChanged: (v) => _set('reunion', v),
                    ),
                  ],
                ),
              ),
              PairPanel(
                child: PTToggleRow(
                  title: 'Quiet hours',
                  subtitle:
                      'Nothing between 11 PM and 8 AM your time, except $partner ringing you.',
                  value: prefs.quietHours,
                  onChanged: (v) => PairService.instance.setPref('quiet_hours', v),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
