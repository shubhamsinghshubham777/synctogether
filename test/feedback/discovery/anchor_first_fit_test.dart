import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:synctogether/feedback/discovery/discovery_anchor.dart';
import 'package:synctogether/rooms/widgets/lobby_header.dart';

void main() {
  testWidgets('the anchor follows the FirstFit candidate that is painted, not a measured one', (
    tester,
  ) async {
    Widget row(Key key, {required double extra}) => Row(
      mainAxisSize: .min,
      mainAxisAlignment: .end,
      children: [
        SizedBox(width: extra, height: 40),
        DiscoveryAnchor(child: SizedBox(key: key, width: 44, height: 44)),
        const SizedBox(width: 40, height: 40),
      ],
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: Align(
          alignment: .topLeft,
          child: SizedBox(
            width: 200,
            child: FirstFit(
              children: [
                row(const ValueKey('chosen'), extra: 0),
                row(const ValueKey('unused'), extra: 20),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final rect = DiscoveryAnchor.activeRect()!;
    expect(rect, tester.getRect(find.byKey(const ValueKey('chosen'))));
  });
}
