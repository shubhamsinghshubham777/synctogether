import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../ui/banners.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/inputs.dart';
import '../ui/pt_theme.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_widgets.dart';
import 'push_service.dart';

/// Rooms, your person, and quiet hours. Only things you would want to know;
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

  Future<void> _retryRegistration() async {
    final ok = await PushService.instance.retryRegistration();
    if (!mounted) return;
    showPTSnack(
      context,
      ok ? 'All set: this phone can get notifications now.' : "Still can't set that up here.",
      kind: ok ? .success : .info,
    );
  }

  /// One card that says what is wrong at the system level and takes the person to
  /// the page that fixes it. The app cannot flip these switches itself.
  Widget _card({
    required String title,
    required String body,
    required List<Widget> actions,
    bool bad = false,
  }) => PairPanel(
    brass: false,
    child: Column(
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        Text(
          title,
          style: PTText.body.copyWith(fontWeight: .w600, color: PTColors.fg),
        ),
        Text(
          body,
          style: PTText.body.copyWith(
            fontSize: 14,
            color: bad ? PTColors.warning : PTColors.fgSoft,
            height: 1.45,
          ),
        ),
        ...actions,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([PairService.instance, PushService.instance]),
      builder: (context, _) {
        final prefs = PairService.instance.prefs;
        final push = PushService.instance;
        final pair = PairService.instance.pair;
        final partner = pair?.partner.displayName.split(' ').first ?? 'your person';
        final denied = push.permission == PushPermission.denied;
        // The OS has the last word: with it off, the switches stay but dim, so a
        // person can still see what they would get.
        Widget dim(Widget child) => denied ? Opacity(opacity: 0.55, child: child) : child;

        return PairPage(
          title: 'Notifications',
          children: [
            Text(
              pair == null
                  ? 'About your rooms. Nothing promotional.'
                  : 'Only things from $partner, your rooms and your plans. Nothing promotional.',
              style: PTText.body.copyWith(color: PTColors.fgSoft, height: 1.5),
            ),
            if (!push.supported)
              const PairPanel(
                child: PairNote(
                  "This device can't receive notifications, so these switches have nothing to send to.",
                ),
              )
            else ...[
              if (denied)
                _card(
                  title: 'Notifications are off for SyncTogether',
                  body:
                      "You'll still see this news inside the app, but not when it's closed. "
                      'Turn them on in system settings to hear when someone sits down.',
                  bad: true,
                  actions: [
                    PTButton(
                      label: 'Open settings',
                      variant: .secondary,
                      icon: BoothIcons.openInNew,
                      height: 42,
                      onPressed: push.openSettings,
                    ),
                  ],
                ),
              if (!denied && push.roomsSilenced)
                _card(
                  title: 'Room alerts are silenced',
                  body:
                      'The "Rooms" category is set to silent in Android, so a seat taken would '
                      'arrive without a sound or a pop-up.',
                  actions: [
                    PTButton(
                      label: 'Open channel settings',
                      variant: .secondary,
                      icon: BoothIcons.openInNew,
                      height: 42,
                      onPressed: push.openRoomsChannelSettings,
                    ),
                  ],
                ),
              if (push.registrationFailed)
                _card(
                  title: "We couldn't set up notifications here",
                  body:
                      "This phone didn't give us a notification address (it happens with no "
                      'Google services, or a poor connection). The banner inside the app still '
                      'works while it is open.',
                  bad: true,
                  actions: [
                    PTButton(
                      label: 'Try again',
                      variant: .secondary,
                      height: 42,
                      onPressed: _retryRegistration,
                    ),
                  ],
                ),
              Text('ROOMS', style: PTText.label),
              dim(
                PairPanel(
                  child: Column(
                    crossAxisAlignment: .stretch,
                    spacing: 10,
                    children: [
                      PTToggleRow(
                        title: 'When someone takes a seat',
                        subtitle:
                            'In a room you host, while you are away from it. '
                            'At most one per room per session.',
                        value: prefs.seatTaken,
                        onChanged: (v) => _set('seat_taken', v),
                      ),
                      if (prefs.seatTaken && prefs.quietHours)
                        Row(
                          spacing: 6,
                          children: [
                            const Icon(BoothIcons.moon, size: 14, color: PTColors.warning),
                            Expanded(
                              child: Text(
                                'Quiet hours 11 PM to 8 AM: held until then',
                                style: PTText.finePrint.copyWith(color: PTColors.warning),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              if (pair != null) ...[
                Text('YOUR PERSON', style: PTText.label),
                dim(
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
                          title: 'Reunion countdown',
                          subtitle: 'Every Sunday, and the day before.',
                          value: prefs.reunion,
                          onChanged: (v) => _set('reunion', v),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              PairPanel(
                child: PTToggleRow(
                  title: 'Quiet hours',
                  subtitle: pair == null
                      ? 'Nothing between 11 PM and 8 AM your time.'
                      : 'Nothing between 11 PM and 8 AM your time, except $partner ringing you.',
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
