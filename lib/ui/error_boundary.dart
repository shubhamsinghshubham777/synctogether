import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../diagnostics.dart';
import 'buttons.dart';
import 'pt_theme.dart';

/// Replaces Flutter's grey release-mode error box with something a person can
/// read, and lets the nearest [PTErrorBoundary] take over the failed region.
///
/// Debug keeps Flutter's red screen: it names the exception and the widget,
/// which is what you want at a desk. Sentry has already been told - the
/// framework reports a build failure through `FlutterError.onError` before it
/// asks this builder for a replacement - so nothing here reports again.
void installFriendlyErrorWidget() {
  if (kDebugMode) return;
  ErrorWidget.builder = (details) => PTErrorFallback(details: details);
}

/// What stands in for the widget that threw while building. A build failure
/// replaces only that widget, so the rest of the screen keeps working; this
/// holds the failed widget's place with a quiet tile and, once mounted, hands
/// the failure to the nearest [PTErrorBoundary] so it can offer a way out.
class PTErrorFallback extends StatefulWidget {
  const PTErrorFallback({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  State<PTErrorFallback> createState() => _PTErrorFallbackState();
}

class _PTErrorFallbackState extends State<PTErrorFallback> {
  @override
  void initState() {
    super.initState();
    // After the frame: the boundary rebuilds in response, which is not
    // allowed while the tree below it is still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.findAncestorStateOfType<_PTErrorBoundaryState>()?._capture(widget.details);
    });
  }

  @override
  Widget build(BuildContext context) {
    // No Theme or Directionality can be assumed this deep inside a failed
    // subtree, so the tile brings its own.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: PTColors.surfaceBase,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Something went wrong here.',
              textAlign: TextAlign.center,
              style: PTText.caption.copyWith(color: PTColors.fgMute),
            ),
          ),
        ),
      ),
    );
  }
}

/// Catches a build failure anywhere below it and swaps [child] for a recovery
/// view: "Try again" re-mounts the child from scratch, and [onExit] (when
/// given) is the way out that does the proper cleanup - a room's leave, say.
///
/// Flutter has no try/catch for build, so this works through
/// [PTErrorFallback]: the failed widget's replacement finds its nearest
/// boundary and reports in. That is also why a boundary only covers *build*
/// failures - an error in an event handler or a future is already
/// non-fatal and reaches Sentry through the zone, with the UI left as it was.
///
/// [compact] is for a panel inside a screen (chat, the video surface): it
/// fills the panel with a small tile instead of taking over the screen.
class PTErrorBoundary extends StatefulWidget {
  const PTErrorBoundary({
    super.key,
    required this.child,
    required this.where,
    this.onExit,
    this.exitLabel = 'Back to lobby',
    this.compact = false,
  });

  final Widget child;

  /// Names the region in the breadcrumb ('room', 'chat'), nothing more.
  final String where;
  final VoidCallback? onExit;
  final String exitLabel;
  final bool compact;

  @override
  State<PTErrorBoundary> createState() => _PTErrorBoundaryState();
}

class _PTErrorBoundaryState extends State<PTErrorBoundary> {
  bool _failed = false;

  /// Bumped on retry so the child is rebuilt from scratch rather than
  /// re-attached to the State that just failed.
  int _generation = 0;

  void _capture(FlutterErrorDetails details) {
    if (_failed || !mounted) return;
    trace(
      'error boundary caught a build failure',
      category: 'ui',
      data: {'where': widget.where, 'error': details.exceptionAsString().split('\n').first},
    );
    setState(() => _failed = true);
  }

  void _retry() {
    trace('error boundary retry', category: 'ui', data: {'where': widget.where});
    setState(() {
      _failed = false;
      _generation++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_failed) return KeyedSubtree(key: ValueKey(_generation), child: widget.child);
    return PTErrorView(
      compact: widget.compact,
      onRetry: _retry,
      onExit: widget.onExit,
      exitLabel: widget.exitLabel,
    );
  }
}

/// The recovery view itself. Friendly copy only - the real cause already left
/// through Sentry.
class PTErrorView extends StatelessWidget {
  const PTErrorView({
    super.key,
    required this.onRetry,
    this.onExit,
    this.exitLabel = 'Back to lobby',
    this.compact = false,
  });

  final VoidCallback onRetry;
  final VoidCallback? onExit;
  final String exitLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: .min,
      children: [
        Text(
          compact ? 'This part hit a snag.' : 'Something hit a snag.',
          textAlign: .center,
          style: compact ? PTText.panelHeading : PTText.screenTitle,
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            compact
                ? "The rest of the room is fine. Give it another go."
                : "We've been told about it. Try again, or head back and pick up from there.",
            textAlign: .center,
            style: PTText.body.copyWith(color: PTColors.fgMute),
          ),
        ),
        SizedBox(height: compact ? 16 : 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: PTButton(label: 'Try again', onPressed: onRetry, height: compact ? 40 : 50),
        ),
        if (onExit != null) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: PTButton(
              label: exitLabel,
              onPressed: onExit,
              variant: .secondary,
              height: compact ? 40 : 50,
            ),
          ),
        ],
      ],
    );
    if (compact) {
      return ColoredBox(
        color: PTColors.surfaceBase,
        child: Center(
          child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body),
        ),
      );
    }
    return Scaffold(
      backgroundColor: PTColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: body),
        ),
      ),
    );
  }
}
