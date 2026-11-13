import 'package:flutter/widgets.dart';

import 'discovery_triggers.dart';

/// Wraps a bug button so the coach mark can point at it. Several can be
/// mounted at once (the lobby under a profile page); the newest is the one on
/// top, so that one is followed.
class DiscoveryAnchor extends StatefulWidget {
  const DiscoveryAnchor({super.key, required this.child});

  final Widget child;

  /// The link of the topmost mounted anchor, or null.
  static final ValueNotifier<LayerLink?> active = ValueNotifier(null);
  static final List<LayerLink> _mounted = [];
  static final Map<LayerLink, GlobalKey> _keys = {};

  /// The topmost anchor's rectangle in window coordinates, or null before it
  /// has been laid out. The coach mark clamps its ring and card against it.
  static Rect? activeRect() {
    final key = _keys[active.value];
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  State<DiscoveryAnchor> createState() => _DiscoveryAnchorState();
}

class _DiscoveryAnchorState extends State<DiscoveryAnchor> {
  final _link = LayerLink();
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    DiscoveryAnchor._keys[_link] = _key;
    DiscoveryAnchor._mounted.add(_link);
    _publish();
  }

  @override
  void dispose() {
    DiscoveryAnchor._mounted.remove(_link);
    DiscoveryAnchor._keys.remove(_link);
    _publish();
    super.dispose();
  }

  void _publish() {
    final top = DiscoveryAnchor._mounted.isEmpty ? null : DiscoveryAnchor._mounted.last;
    // Notifying mid-build/unmount is illegal; hop to the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DiscoveryAnchor.active.value = top;
      DiscoveryTriggers.instance.anchorChanged(top != null);
    });
  }

  @override
  Widget build(BuildContext context) =>
      CompositedTransformTarget(key: _key, link: _link, child: widget.child);
}
