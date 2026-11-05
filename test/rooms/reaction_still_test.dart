import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:synctogether/rooms/reactions.dart';

/// Fraction of a 64px square the still covers with visible pixels.
Future<double> _coverage(WidgetTester tester, LottieComposition c, double progress) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(
            dimension: 64,
            child: RawLottie(composition: c, progress: progress, fit: BoxFit.contain),
          ),
        ),
      ),
    ),
  );
  return (await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var visible = 0;
    for (var i = 3; i < data.lengthInBytes; i += 4) {
      if (data.getUint8(i) > 16) visible++;
    }
    return visible / (image.width * image.height);
  }))!;
}

void main() {
  test('every still override targets a known reaction and a valid progress', () {
    final known = kAllReactions.map((r) => r.codepoint).toSet();
    for (final entry in kReactionStillProgress.entries) {
      expect(known, contains(entry.key));
      expect(entry.value, inInclusiveRange(0.0, 1.0));
    }
  });

  for (final reaction in kReactions) {
    testWidgets('${reaction.label} still frame is not blank or undersized', (tester) async {
      final bytes = File(reaction.asset).readAsBytesSync();
      final composition = (await tester.runAsync(() => LottieComposition.fromBytes(bytes)))!;
      final coverage = await _coverage(tester, composition, reaction.stillProgress);
      expect(coverage, greaterThan(0.2), reason: '${reaction.codepoint} still is too empty');
    });
  }

  testWidgets('the party popper still carries confetti, unlike frame 0', (tester) async {
    final party = reactionForEmoji('🎉')!;
    final composition = (await tester.runAsync(
      () => LottieComposition.fromBytes(File(party.asset).readAsBytesSync()),
    ))!;
    final first = await _coverage(tester, composition, 0);
    final still = await _coverage(tester, composition, party.stillProgress);
    expect(still, greaterThan(first));
  });
}
