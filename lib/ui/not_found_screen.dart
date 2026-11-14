import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../diagnostics.dart';
import 'booth_icons.g.dart';
import 'buttons.dart';
import 'pt_motion.dart';
import 'pt_theme.dart';

/// Longest path kept in the breadcrumb; anything past it is noise.
const _kMaxLoggedPath = 120;

/// What the app shows for a location no route matches - the in-app twin of the
/// website's `app/not-found.tsx` (board 44): compass tile, mono eyebrow,
/// display title, one line of copy and a single way home.
///
/// A signed-out visitor never sees it for long: the router's redirect sends
/// them on from the lobby to sign-in, so [onHome] always targets the lobby.
///
/// [location] is only ever the *path* of what was asked for; the query and
/// fragment are dropped before it gets here, because on a callback they can
/// carry tokens.
class NotFoundScreen extends StatefulWidget {
  const NotFoundScreen({super.key, required this.location, required this.onHome});

  final String location;
  final VoidCallback onHome;

  @override
  State<NotFoundScreen> createState() => _NotFoundScreenState();
}

class _NotFoundScreenState extends State<NotFoundScreen> {
  @override
  void initState() {
    super.initState();
    // Once per mount, not per build: an unmatched link is an expected outcome
    // (stale invite, old bookmark), so it is a breadcrumb, not an error.
    final path = widget.location;
    trace(
      'no route for location',
      category: 'deeplink',
      data: {'path': path.length > _kMaxLoggedPath ? path.substring(0, _kMaxLoggedPath) : path},
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final body = Column(
      mainAxisSize: .min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: PTColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(PTRadius.panel),
            border: Border.all(color: PTColors.primary.withValues(alpha: 0.20)),
          ),
          child: const ExcludeSemantics(
            child: Icon(Symbols.explore_rounded, size: 32, color: PTColors.accentSoft),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'ERROR 404',
          style: PTText.label.copyWith(
            fontSize: 12,
            fontWeight: .w600,
            letterSpacing: 2.4,
            color: PTColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Lost in sync',
          textAlign: .center,
          style: PTText.display.copyWith(fontSize: wide ? 48 : 40, letterSpacing: -1.2),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(
            "This page doesn't exist, was moved, or needs access you don't have.",
            textAlign: .center,
            style: PTText.body.copyWith(
              fontSize: wide ? 16 : 15,
              height: 1.5,
              color: PTColors.fgMute,
            ),
          ),
        ),
        const SizedBox(height: 28),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 280 : double.infinity),
          child: PTButton(
            label: 'Back to lobby',
            icon: BoothIcons.arrowBack,
            onPressed: widget.onHome,
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: PTColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              // Centres short content; taller (large text) simply scrolls.
              constraints: BoxConstraints(minHeight: box.maxHeight - 64),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: reducedMotion(context) ? 1 : 0, end: 1),
                    duration: PTMotion.entrance,
                    curve: PTMotion.enter,
                    builder: (context, t, child) => Opacity(
                      opacity: t,
                      child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
                    ),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
