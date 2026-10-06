import 'package:flutter/material.dart';
import 'package:synctogether/ui/pt_motion.dart';

/// Animated container that holds stacked room banners (reconnecting, warnings, upload progress).
class RoomBannerStack extends StatelessWidget {
  const RoomBannerStack({
    required this.banners,
    required this.spacing,
    this.padding = EdgeInsets.zero,
    this.inScroll = false,
    super.key,
  });

  final List<Widget> banners;
  final double spacing;
  final EdgeInsets padding;
  final bool inScroll;

  @override
  Widget build(BuildContext context) {
    final column = Column(spacing: spacing, children: banners);
    return AnimatedSize(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      alignment: Alignment.topCenter,
      child: banners.isEmpty
          ? const SizedBox.shrink()
          : inScroll
          ? Padding(padding: padding, child: column)
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height / 3),
              child: SingleChildScrollView(padding: padding, child: column),
            ),
    );
  }
}
