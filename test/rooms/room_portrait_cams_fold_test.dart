import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/widgets/room_mobile_layout.dart';

const _cams = Key('cams');
const _chat = Key('video');

Widget _layout({required bool cams}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 390,
      height: 844,
      child: RoomMobilePortraitLayout(
        header: const SizedBox(height: 56),
        videoSurface: const SizedBox.expand(key: _chat),
        reactionStrip: const SizedBox(height: 40),
        controlBar: const SizedBox(height: 64),
        bannerStack: const SizedBox.shrink(),
        embeddedChat: const SizedBox.expand(),
        facecamStrip: cams ? const SizedBox(key: _cams, height: 90) : null,
      ),
    ),
  ),
);

void main() {
  testWidgets('turning cams off folds the strip away instead of popping it', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The picture is what the strip's height goes to once the chat is at its floor.
    final chatSlot = find.byType(RoomPortraitSlot).last;
    double chatHeight() => tester.getSize(chatSlot).height;

    await tester.pumpWidget(_layout(cams: true));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_cams)).height, 90);
    final before = chatHeight();

    await tester.pumpWidget(_layout(cams: false));
    final heights = <double>[];
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.byKey(_cams), findsOneWidget, reason: 'still mounted mid-fold, frame $i');
      heights.add(chatHeight());
    }
    expect(heights.first, greaterThanOrEqualTo(before));
    expect(heights.first, lessThan(before + 106), reason: 'not the whole strip in one frame');
    expect(heights.toSet().length, greaterThan(2), reason: 'it eases over frames: $heights');
    for (var i = 1; i < heights.length; i++) {
      expect(heights[i], greaterThanOrEqualTo(heights[i - 1]));
    }
    await tester.pumpAndSettle();
    expect(find.byKey(_cams), findsNothing, reason: 'unmounted once folded');
    expect(chatHeight(), greaterThan(before + 20));

    // And it folds back in.
    await tester.pumpWidget(_layout(cams: true));
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byKey(_cams), findsOneWidget);
    expect(chatHeight(), lessThan(before + 106));
    await tester.pumpAndSettle();
    expect(chatHeight(), closeTo(before, 0.5));
  });
}
