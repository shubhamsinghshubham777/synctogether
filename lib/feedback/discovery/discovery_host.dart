import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../platform.dart';
import '../../ui/banners.dart';
import '../../ui/booth_icons.g.dart';
import '../../ui/buttons.dart';
import '../../ui/pt_motion.dart';
import '../../ui/pt_theme.dart';
import '../feedback_analytics.dart';
import '../shake_to_report.dart';
import 'open_report.dart';
import '../contract.dart';
import '../fixed_from.dart';
import 'coach_geometry.dart';
import 'coach_scrim.dart';
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
            _CoachMark(
              onDismiss: ({required tracked}) {
                // Tapping the lit button opens the report (its own event), so
                // only a dismissal that was just a dismissal is counted.
                if (tracked) FeedbackAnalytics.introDismissed();
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

/// A still Beam ring on the bug button with one ripple, and a card beneath it
/// with an arrow, over a dim of the rest of the window with a hole where the
/// button is ([CoachScrim]). Everything is placed from the button's real
/// rectangle (see [CoachGeometry]) so the ring and the card stay inside the
/// window wherever the button sits. The ripple plays once (a looping pulse would
/// repaint forever); reduce-motion draws the ring still and shortens the fade.
///
/// It is a hint, not a modal: a tap on the dim, Escape or "Got it" all end it
/// (and count as seen); a tap on the lit button ends it too and still reaches
/// the button.
class _CoachMark extends StatefulWidget {
  const _CoachMark({required this.onDismiss});

  /// [tracked] is false when the dismissal was a tap on the bug button itself.
  final void Function({required bool tracked}) onDismiss;

  @override
  State<_CoachMark> createState() => _CoachMarkState();
}

class _CoachMarkState extends State<_CoachMark> with SingleTickerProviderStateMixin {
  Rect? _anchor;
  final _cardKey = GlobalKey();
  double _cardHeight = 0;
  late final AnimationController _fade = AnimationController(vsync: this);
  bool _started = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _measure();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Functional motion: shorter under reduce-motion, never removed.
    _fade.animateTo(
      1,
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _fade.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape || _closing) return false;
    _close(tracked: true);
    return true;
  }

  /// Fades the dim and the card away, then tells the host (which saves "seen").
  void _close({required bool tracked}) {
    if (_closing) return;
    _closing = true;
    _fade
        .animateBack(
          0,
          duration: PTMotion.functional(context, PTMotion.hover),
          curve: PTMotion.exit,
        )
        .whenComplete(() {
          if (mounted) widget.onDismiss(tracked: tracked);
        });
  }

  @override
  void didUpdateWidget(_CoachMark old) {
    super.didUpdateWidget(old);
    _measure();
  }

  /// The button is laid out before this widget builds, but its rectangle is only
  /// readable once the frame is done; read it again then so a move (a resize, a
  /// different header) is followed.
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final now = DiscoveryAnchor.activeRect();
      final h = (_cardKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
      if (now != _anchor || (h - _cardHeight).abs() > 0.5) {
        setState(() {
          _anchor = now;
          _cardHeight = h;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final anchor = _anchor ?? DiscoveryAnchor.activeRect();
    if (anchor == null) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    // A keyboard that is up counts as the bottom edge of the window.
    final keys = MediaQuery.viewInsetsOf(context).bottom;
    final geo = CoachGeometry.compute(
      anchor: anchor,
      window: size,
      safe: pad.copyWith(bottom: keys > pad.bottom ? keys : pad.bottom),
      cardHeight: _cardHeight,
    );
    final still = reducedMotion(context);
    final area = geo.ringArea;
    final lit = geo.anchor.inflate(geo.ringOutset + CoachScrim.holeGap);
    final hole = RRect.fromRectAndRadius(
      lit,
      Radius.circular(PTRadius.control + geo.ringOutset + CoachScrim.holeGap),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: CoachScrim(fade: _fade, hole: hole, onTap: () => _close(tracked: true)),
        ),
        // The lit button is the one place the dim lets taps through. This only
        // listens: the button still gets the tap, and the mark ends with it.
        Positioned.fromRect(
          rect: lit,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _close(tracked: false),
          ),
        ),
        Positioned.fromRect(
          rect: area,
          child: IgnorePointer(
            child: FadeTransition(
              opacity: _fade,
              child: TweenAnimationBuilder<double>(
                key: const ValueKey('coach-ring'),
                tween: Tween(begin: still ? 1 : 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => CustomPaint(
                  painter: _RingPainter(geo: geo, ripple: t),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: geo.card.left,
          top: geo.card.top,
          width: geo.card.width,
          // Invisible for the one frame it takes to measure the card, so it never
          // flashes in a spot it then leaves.
          child: Opacity(
            opacity: _cardHeight > 0 ? 1 : 0,
            child: FadeTransition(
              opacity: _fade,
              child: PTEntrance(
                offset: -6,
                duration: PTMotion.state,
                child: _CoachCard(
                  key: _cardKey,
                  side: geo.side,
                  arrow: geo.arrow,
                  maxHeight: geo.maxHeight,
                  onDone: () => _close(tracked: true),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The still ring, its faint halo (only where there is room) and the single
/// ripple. Paints inside [CoachGeometry.ringArea], which is inside the window.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.geo, required this.ripple});

  final CoachGeometry geo;

  /// 0 at the start of the ripple, 1 when it has faded out.
  final double ripple;

  RRect _ring(double outset) => RRect.fromRectAndRadius(
    geo.anchor.inflate(outset).shift(-geo.ringArea.topLeft),
    Radius.circular(PTRadius.control + outset),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final o = geo.ringOutset;
    if (geo.halo > 0) {
      canvas.drawRRect(
        _ring(o + geo.halo / 2 + 0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = geo.halo
          ..color = PTColors.primary.withValues(alpha: 0.16),
      );
    }
    canvas.drawRRect(
      _ring(o),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = PTColors.primary,
    );
    if (ripple < 1 && geo.rippleOutset > o) {
      canvas.drawRRect(
        _ring(o + (geo.rippleOutset - o) * ripple),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = PTColors.primary.withValues(alpha: 0.6 * (1 - ripple)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.ripple != ripple || old.geo != geo;
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({
    super.key,
    required this.side,
    required this.arrow,
    required this.maxHeight,
    required this.onDone,
  });

  final CoachSide side;
  final double arrow;
  final double maxHeight;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PTColors.glassBase,
              border: Border.all(color: PTColors.rail),
              borderRadius: BorderRadius.circular(PTRadius.panel),
            ),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              spacing: 8,
              children: [
                // The words scroll if the window is shorter than the card; the
                // button below them never leaves the screen.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 8,
                      children: [
                        Text(
                          'Hit a snag? Tap the bug.',
                          style: PTText.cardHeading.copyWith(fontSize: 17),
                        ),
                        Text(
                          'We get a screenshot and the details, you get a fix. One tap, no forms.',
                          style: PTText.body.copyWith(
                            fontSize: 13,
                            color: PTColors.fgDim,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: PTButton(label: 'Got it', height: 34, expand: false, onPressed: onDone),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: side == CoachSide.below ? arrow - 6 : null,
          right: side == CoachSide.left ? -6 : null,
          top: side == CoachSide.below ? -6 : arrow - 6,
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: PTColors.glassBase,
                // The two edges that face away from the card carry the hairline.
                border: side == CoachSide.below
                    ? const Border(
                        left: BorderSide(color: PTColors.rail),
                        top: BorderSide(color: PTColors.rail),
                      )
                    : const Border(
                        right: BorderSide(color: PTColors.rail),
                        top: BorderSide(color: PTColors.rail),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
