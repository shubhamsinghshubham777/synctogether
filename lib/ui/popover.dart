import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pt_motion.dart';

/// A live handle on a popover opened by [showPTPopover].
class PTPopoverHandle {
  PTPopoverHandle._();

  final _closed = Completer<void>();
  _PTPopoverHostState? _host;
  OverlayEntry? _entry;

  /// Completes once the popover has left the overlay.
  Future<void> get closed => _closed.future;

  bool get isOpen => !_closed.isCompleted;

  /// Plays the exit and removes the popover. [animate] false removes it on
  /// this frame - for eviction and teardown, where nobody is watching.
  void close({bool animate = true}) {
    if (!isOpen) return;
    final host = _host;
    if (animate && host != null && host.mounted) {
      host._exit();
    } else {
      _remove();
    }
  }

  void _remove() {
    if (!isOpen) return;
    _entry?.remove();
    _entry = null;
    _closed.complete();
  }
}

/// A lightweight anchored popup: an [OverlayEntry], not a route.
///
/// `showGeneralDialog` pushes a whole `ModalRoute` - navigator rebuild, focus
/// scope, barrier semantics, a route transition on the page underneath - which
/// on the room screen means a frame budget shared with playing video. This
/// inserts one entry into the root overlay and drives it with one controller.
/// The content is built once behind a [RepaintBoundary], so the fade and rise
/// only move a cached layer: nothing inside repaints while it animates, and
/// there is no scale (scaling re-rasterises text and the panel's shadow every
/// frame).
///
/// [builder] fills the overlay and places its own panel - typically
/// `SafeArea` > `Align` > the panel.
///
/// Dismissed by a tap outside, Esc, or [PTPopoverHandle.close]. A system back
/// gesture is the owner's to route: an overlay entry sits outside the page's
/// `PopScope`, so the owner closes the handle there first.
PTPopoverHandle showPTPopover({
  required BuildContext context,
  required WidgetBuilder builder,
  double rise = 6,
}) {
  final handle = PTPopoverHandle._();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => _PTPopoverHost(handle: handle, builder: builder, rise: rise),
  );
  handle._entry = entry;
  overlay.insert(entry);
  return handle;
}

class _PTPopoverHost extends StatefulWidget {
  const _PTPopoverHost({required this.handle, required this.builder, required this.rise});

  final PTPopoverHandle handle;
  final WidgetBuilder builder;
  final double rise;

  @override
  State<_PTPopoverHost> createState() => _PTPopoverHostState();
}

class _PTPopoverHostState extends State<_PTPopoverHost> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PTMotion.hover,
    reverseDuration: const Duration(milliseconds: 100),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: PTMotion.enter,
    reverseCurve: PTMotion.exit,
  );
  final _focus = FocusNode(debugLabel: 'popover');
  final FocusNode? _previousFocus = FocusManager.instance.primaryFocus;

  @override
  void initState() {
    super.initState();
    widget.handle._host = this;
    _controller.forward();
    // Not `autofocus`: an overlay entry sits outside any route's focus scope,
    // so autofocus never claims the keyboard and Esc would go to the page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) _controller.duration = PTMotion.tap;
  }

  void _exit() {
    if (_controller.status == AnimationStatus.reverse) return;
    _controller.reverse().whenCompleteOrCancel(widget.handle._remove);
  }

  @override
  void dispose() {
    if (widget.handle._host == this) widget.handle._host = null;
    // Hand the keyboard back to whoever had it (the room's shortcuts).
    if (_focus.hasFocus && (_previousFocus?.canRequestFocus ?? false)) {
      _previousFocus!.requestFocus();
    }
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          widget.handle.close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // Transparent barrier: a tap outside closes, and is not passed on to
          // the video (the old route barrier swallowed it the same way).
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.handle.close),
          ),
          // The builder positions its own panel (an Align inside it), so the
          // empty space around the panel hit-tests through to the barrier.
          Positioned.fill(
            child: FadeTransition(
              opacity: _curve,
              child: AnimatedBuilder(
                animation: _curve,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, -widget.rise * (1 - _curve.value)),
                  child: child,
                ),
                child: RepaintBoundary(child: Builder(builder: widget.builder)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
