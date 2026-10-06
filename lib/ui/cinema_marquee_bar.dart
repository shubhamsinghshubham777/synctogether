import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../platform.dart';
import 'pt_theme.dart';

/// The unified desktop system bar for the projection booth cinema aesthetic.
///
/// Replaces the plain native title bar with a bespoke strip that:
/// - Reserves an inset for macOS traffic light buttons on the top left; the
///   native window places them on this bar's vertical centre line
///   (`MainFlutterWindow.placeTrafficLights`).
/// - Unifies screen navigation and headers directly into the window frame.
/// - Covers empty spaces with [DragToMoveArea] for window dragging and
///   double-click maximize/restore.
/// - Provides custom Windows caption buttons (min, max/restore, close) on
///   Windows so window management is never lost.
class CinemaMarqueeBar extends StatelessWidget {
  const CinemaMarqueeBar({
    super.key,
    this.leading,
    this.center,
    this.trailing,
    this.child,
    this.height = 52.0,
    this.border = true,
    this.backgroundColor,
    this.fullscreen = false,
  });

  /// Widget placed after the macOS traffic light inset (or at the start on Windows/Linux).
  final Widget? leading;

  /// Optional widget placed in the center of the draggable marquee.
  final Widget? center;

  /// Optional actions or status widgets placed before the Windows caption controls.
  final Widget? trailing;

  /// Optional full-width content placed between macOS traffic lights and Windows buttons.
  /// If provided, [leading], [center], and [trailing] are ignored.
  final Widget? child;

  /// Height of the marquee bar. Defaults to 52.0 px.
  final double height;

  /// Whether to render a subtle bottom hairline border. Defaults to true.
  final bool border;

  /// Optional background override. Defaults to [PTColors.canvas].
  final Color? backgroundColor;

  /// Whether the window is currently in fullscreen mode.
  ///
  /// When true, collapses the macOS traffic light inset to 0 px and omits
  /// Windows caption controls and dragging areas.
  final bool fullscreen;

  /// Standard inset reserved for native macOS window controls (traffic lights).
  static const double macOsTrafficLightInset = 86.0;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return const SizedBox.shrink();

    final isMac = defaultTargetPlatform == .macOS;
    final isWindows = defaultTargetPlatform == .windows;
    final effectiveMacInset = isMac && !fullscreen ? macOsTrafficLightInset : 0.0;
    final showWindowsButtons = isWindows && !fullscreen;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? PTColors.canvas,
        border: border ? const Border(bottom: BorderSide(color: PTColors.aisle, width: 1.0)) : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!fullscreen)
            Positioned(
              left: effectiveMacInset,
              right: showWindowsButtons ? 138 : 0,
              top: 0,
              bottom: 0,
              child: const DragToMoveArea(child: SizedBox.expand()),
            ),
          Row(
            crossAxisAlignment: .stretch,
            children: [
              if (effectiveMacInset > 0) SizedBox(width: effectiveMacInset),
              if (child != null)
                Expanded(child: child!)
              else ...[
                if (leading != null) Center(child: leading!),
                Expanded(child: center != null ? Center(child: center!) : const SizedBox.expand()),
                if (trailing != null) Center(child: trailing!),
              ],
              if (showWindowsButtons) WindowsCaptionButtons(height: height),
            ],
          ),
        ],
      ),
    );
  }
}

class WindowsCaptionButtons extends StatefulWidget {
  const WindowsCaptionButtons({required this.height, super.key});

  final double height;

  @override
  State<WindowsCaptionButtons> createState() => _WindowsCaptionButtonsState();
}

class _WindowsCaptionButtonsState extends State<WindowsCaptionButtons> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    try {
      windowManager.addListener(this);
    } catch (_) {}
    unawaited(_checkMaximized());
  }

  Future<void> _checkMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted && maximized != _isMaximized) {
        setState(() => _isMaximized = maximized);
      }
    } catch (_) {
      // In widget tests or uninitialized desktop channels, windowManager might throw.
    }
  }

  @override
  void dispose() {
    try {
      windowManager.removeListener(this);
    } catch (_) {}
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        _CaptionButton(
          tooltip: 'Minimize',
          onPressed: () async {
            try {
              await windowManager.minimize();
            } catch (_) {}
          },
          icon: Container(width: 10, height: 1.2, color: PTColors.fgDim),
        ),
        _CaptionButton(
          tooltip: _isMaximized ? 'Restore' : 'Maximize',
          onPressed: () async {
            try {
              if (_isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            } catch (_) {}
          },
          icon: _isMaximized
              ? CustomPaint(
                  size: const Size(10, 10),
                  painter: const _RestoreIconPainter(color: PTColors.fgDim),
                )
              : Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(border: Border.all(color: PTColors.fgDim, width: 1.2)),
                ),
        ),
        _CaptionButton(
          tooltip: 'Close',
          isClose: true,
          onPressed: () async {
            try {
              await windowManager.close();
            } catch (_) {}
          },
          icon: const Icon(Icons.close_rounded, size: 14, color: PTColors.fgDim),
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final closeHover = PTColors.windowsCloseHover;
    final normalHover = PTColors.white(0.08);

    final bg = _hovered ? (widget.isClose ? closeHover : normalHover) : Colors.transparent;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 700),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: .opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            color: bg,
            alignment: .center,
            child: widget.isClose && _hovered
                ? const Icon(Icons.close_rounded, size: 14, color: Colors.white)
                : widget.icon,
          ),
        ),
      ),
    );
  }
}

class _RestoreIconPainter extends CustomPainter {
  const _RestoreIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 1.0;

    // Back square (offset up and right)
    canvas.drawRect(Rect.fromLTWH(2, 0, size.width - 2, size.height - 2), paint);
    // Front square (bottom left)
    canvas.drawRect(Rect.fromLTWH(0, 2, size.width - 2, size.height - 2), paint);
  }

  @override
  bool shouldRepaint(covariant _RestoreIconPainter oldDelegate) => oldDelegate.color != color;
}
