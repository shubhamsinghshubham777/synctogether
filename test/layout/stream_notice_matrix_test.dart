import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/stream/stream_health.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

/// The three stream-notice banners (design board 51) exactly as RoomScreen
/// builds them, across the whole device and text-scale matrix.
void main() {
  screenMatrix('room/stream-notices', (tester, c, s) async {
    await pumpAtSize(
      tester,
      Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              spacing: 8,
              children: [
                PTBanner(
                  kind: .info,
                  icon: BoothIcons.clock,
                  title: 'Buffering a little more',
                  subtitle: 'Smoothing things out so it plays without pauses.',
                  showActivity: true,
                  onDismiss: () {},
                ),
                PTBanner(
                  kind: .info,
                  icon: BoothIcons.info,
                  title: 'This video is high quality (${formatMbps(38.4e6)})',
                  subtitle:
                      'Your connection looks like it can keep up with ${formatMbps(21.6e6)} right now, '
                      'so it may pause now and then. You can let it buffer ahead first.',
                  trailing: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PTButton(
                        label: 'Buffer ahead',
                        variant: .primary,
                        height: 36,
                        expand: false,
                        onPressed: () {},
                      ),
                      PTButton(
                        label: 'Keep going',
                        variant: .secondary,
                        height: 36,
                        expand: false,
                        onPressed: () {},
                      ),
                    ],
                  ),
                  onDismiss: () {},
                ),
                PTBanner(
                  kind: .info,
                  icon: BoothIcons.clock,
                  title: 'Buffering ahead',
                  subtitle: 'About 12 s of 30 s is ready. You will show as loading to the room until then.',
                  showActivity: true,
                  trailing: PTButton(
                    label: 'Start anyway',
                    variant: .secondary,
                    height: 36,
                    expand: false,
                    onPressed: () {},
                  ),
                  onDismiss: () {},
                ),
              ],
            ),
          ),
        ),
      ),
      c,
      textScale: s,
    );
    expect(find.text('Buffer ahead'), findsOneWidget);
    expect(find.text('Keep going'), findsOneWidget);
    expect(find.text('Start anyway'), findsOneWidget);
    await finishCase(tester);
  });
}
