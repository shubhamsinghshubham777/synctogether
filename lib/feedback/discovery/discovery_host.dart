import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../platform.dart';
import '../../ui/banners.dart';
import '../../ui/booth_icons.g.dart';
import '../../ui/buttons.dart';
import '../../ui/coach_mark.dart';
import '../../ui/pt_motion.dart';
import '../feedback_analytics.dart';
import '../shake_to_report.dart';
import 'open_report.dart';
import '../contract.dart';
import '../fixed_from.dart';
import 'discovery_anchor.dart';
import 'discovery_logic.dart';
import 'discovery_triggers.dart';

/// Draws what [DiscoveryTriggers] wants on top of the whole app: the nudge
/// banner (anywhere), the "fixed" banner (lobby only) and the coach mark.
/// An overlay, not a route, like `PTSplash`, so it never disturbs navigation.
class DiscoveryHost extends StatefulWidget {
  const DiscoveryHost({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  State<DiscoveryHost> createState() => _DiscoveryHostState();
}

class _DiscoveryHostState extends State<DiscoveryHost> {
  DiscoveryTriggers get _t => DiscoveryTriggers.instance;

  @override
  void initState() {
    super.initState();
    _t.start();
    unawaited(ShakeToReport.instance.attach(widget.router));
  }

  @override
  void dispose() {
    ShakeToReport.instance.detach(widget.router);
    super.dispose();
  }

  String get _path => widget.router.routerDelegate.currentConfiguration.uri.path;

  Future<void> _openReport() async {
    // The host sits above the Navigator, so the sheet needs the router's own.
    final ctx = widget.router.routerDelegate.navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) await openReportFrom(ctx, 'nudge');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned.fill(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _t,
              ShakeToReport.instance.introPending,
              widget.router.routerDelegate,
              DiscoveryAnchor.active,
            ]),
            builder: (context, _) => _overlay(context),
          ),
        ),
      ],
    );
  }

  Widget _overlay(BuildContext context) {
    final path = _path;
    final inRoom = path.startsWith('/lobby/room');
    final onLogin = path == '/login';
    final nudge = _t.nudge;
    final fixed = path == '/lobby' ? _t.fixedBanner : null;
    final link = DiscoveryAnchor.active.value;
    final coach = _t.coachVisible && !inRoom && !onLogin && link != null;
    final banner = nudge != null
        ? _nudgeBanner(nudge)
        : fixed != null
        ? _fixedBanner(fixed)
        : ShakeToReport.instance.introPending.value
        ? _shakeIntroBanner()
        : null;
    final pad = MediaQuery.paddingOf(context);
    final top = pad.top + (isDesktop ? 60 : 8);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (banner != null)
            Positioned(
              top: top,
              left: 16 + pad.left,
              right: 16 + pad.right,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: banner,
                ),
              ),
            ),
          if (coach)
            CoachMark(
              anchor: DiscoveryAnchor.activeRect,
              title: 'Hit a snag? Tap the bug.',
              body: 'We get a screenshot and the details, you get a fix. One tap, no forms.',
              onEnd: (end) {
                // Tapping the lit button opens the report (its own event), so
                // only a dismissal that was just a dismissal is counted.
                if (end != CoachEnd.target) FeedbackAnalytics.introDismissed();
                _t.dismissCoach();
              },
            ),
        ],
      ),
    );
  }

  Widget _nudgeBanner(NudgeReason reason) => PTEntrance(
    key: const ValueKey('nudge'),
    offset: -8,
    duration: PTMotion.state,
    child: PTBanner(
      kind: .info,
      icon: BoothIcons.bug,
      title: nudgeCopyTitle(reason),
      subtitle: nudgeCopyBody(reason),
      trailing: PTButton(
        label: reason == NudgeReason.previousCrash ? 'Send' : 'Send a report',
        height: 34,
        expand: false,
        onPressed: () {
          FeedbackAnalytics.nudgeTapped(nudgeAnalyticsReason(reason));
          _t.answerNudge(accepted: true);
          _openReport();
        },
      ),
      autoDismissAfter: const Duration(seconds: 12),
      onDismiss: () => _t.answerNudge(accepted: false),
    ),
  );

  /// Once ever, after the first shake-opened report is sent or dismissed: say
  /// what just happened and offer the way out (board 86, pane 03). No countdown;
  /// closing it counts as keeping shake on.
  Widget _shakeIntroBanner() => PTEntrance(
    key: const ValueKey('shake-intro'),
    offset: -8,
    duration: PTMotion.state,
    child: PTBanner(
      kind: .info,
      icon: BoothIcons.bug,
      title: 'Shaking opens bug reports.',
      subtitle: 'Keep it on? Change it in Profile.',
      // PTBanner drops a trailing action beneath the text when narrow; a Wrap
      // keeps the two buttons side by side there and wraps them only when the
      // width (large text, a cover display) cannot hold both.
      trailing: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          PTButton(
            label: 'Keep it',
            height: 34,
            expand: false,
            onPressed: () => ShakeToReport.instance.answerIntro(keep: true),
          ),
          PTButton(
            label: 'Turn off',
            variant: .secondary,
            height: 34,
            expand: false,
            onPressed: () => ShakeToReport.instance.answerIntro(keep: false),
          ),
        ],
      ),
      onDismiss: () => ShakeToReport.instance.answerIntro(keep: true),
    ),
  );

  Widget _fixedBanner(BugReportRow row) => PTEntrance(
    key: ValueKey('fixed-${row.code}'),
    offset: -8,
    duration: PTMotion.state,
    child: PTBanner(
      kind: .info,
      icon: BoothIcons.check,
      title: row.fixedIn == null ? 'Fixed' : 'Fixed from ${row.fixedIn} onward',
      subtitle:
          'The "${row.title}" bug you reported (${row.code}). ${fixedBannerTail(row.fixedIn)}',
      trailing: !showUpdateFor(row.fixedIn, canUpdate: DiscoveryTriggers.onUpdate != null)
          ? null
          : PTButton(
              label: 'Update',
              variant: .secondary,
              height: 34,
              expand: false,
              onPressed: DiscoveryTriggers.onUpdate,
            ),
      onDismiss: _t.dismissFixed,
    ),
  );
}
