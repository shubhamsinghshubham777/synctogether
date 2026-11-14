import 'dart:async';

import 'package:synctogether/feedback/ui/bug_report_button.dart';
import 'package:material_ui/material_ui.dart';
import 'package:synctogether/ui/escape_back.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:synctogether/window/app_window.dart';

import '../nav.dart';
import '../platform.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/cinema_marquee_bar.dart';
import '../ui/glass.dart';
import '../ui/pt_theme.dart';
import '../ui/scroll_fade.dart';

/// The frame every pair screen shares: the desktop marquee bar or a plain header
/// with a back button and a title, then one centred, scrolling column.
///
/// It exists so the six pair screens cannot drift apart - they differ in what
/// they show, never in how they sit on the page. Detail pages of the lobby are
/// already hinge-safe through the router, so this does not repeat that.
class PairPage extends StatefulWidget {
  const PairPage({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.footer,
    this.maxWidth = 560,
    this.spacing = 14,
  });

  final String title;
  final List<Widget> children;

  /// Right-aligned header content (an add button).
  final Widget? trailing;

  /// Pinned under the scrolling column: the primary action.
  final Widget? footer;
  final double maxWidth;
  final double spacing;

  @override
  State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> with AppWindowListener {
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    if (isDesktop) {
      AppWindow.instance.addListener(this);
      unawaited(_syncFullscreen());
    }
  }

  /// Seeds the flag from the window, which may already be fullscreen when this
  /// page opens. A window with no native side (a test harness) just means "no".
  Future<void> _syncFullscreen() async {
    try {
      final v = await AppWindow.instance.isFullScreen();
      if (mounted && v != _fullscreen) setState(() => _fullscreen = v);
    } on MissingPluginException {
      // Nothing to read.
    }
  }

  @override
  void dispose() {
    if (isDesktop) AppWindow.instance.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() => setState(() => _fullscreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullscreen = false);

  Widget _back({double size = 44, double iconSize = 20}) => Row(
    mainAxisSize: .min,
    spacing: 14,
    children: [
      PTIconButton(
        icon: BoothIcons.arrowBack,
        size: size,
        iconSize: iconSize,
        tooltip: 'Back',
        onPressed: () => goBack(context),
      ),
      Flexible(
        child: Text(widget.title, maxLines: 1, overflow: .ellipsis, style: PTText.cardHeading),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final gutter = MediaQuery.sizeOf(context).width >= 720 ? 48.0 : 20.0;
    return PTEscapeBack(
      child: Scaffold(
        body: AmbientBackground(
          child: SafeArea(
            top: !isDesktop,
            child: Column(
              children: [
                if (isDesktop)
                  CinemaMarqueeBar(
                    height: 52,
                    fullscreen: _fullscreen,
                    leading: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: _back(size: 36, iconSize: 18),
                    ),
                    trailing: widget.trailing,
                  )
                else
                  Padding(
                    padding: EdgeInsets.fromLTRB(gutter - 8, 10, gutter, 6),
                    child: Row(
                      children: [
                        Expanded(child: _back()),
                        ?widget.trailing,
                        const BugReportButton(),
                      ],
                    ),
                  ),
                Expanded(
                  child: ScrollFadeEdge(
                    height: 36,
                    child: SingleChildScrollView(
                      keyboardDismissBehavior: .onDrag,
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        18,
                        gutter,
                        widget.footer == null ? 48 : 20,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: widget.maxWidth),
                          child: Column(
                            crossAxisAlignment: .stretch,
                            spacing: widget.spacing,
                            children: widget.children,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.footer != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      8,
                      gutter,
                      14 + MediaQuery.paddingOf(context).bottom * 0.5,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: widget.maxWidth),
                        child: widget.footer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
