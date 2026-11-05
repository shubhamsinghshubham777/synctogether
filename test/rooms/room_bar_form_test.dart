// The room control bar's form ladder (board 46), as pure decisions: which form
// a slot width picks, what each form folds, the facecam rail's height rule and
// the chat's width formula. No render tree.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/widgets/room_bar_form.dart';

const _phone = RoomBarCaps(
  controls: {
    BarControl.mic,
    BarControl.camera,
    BarControl.react,
    BarControl.skipBack,
    BarControl.skipForward,
    BarControl.source,
    BarControl.openFile,
    BarControl.audio,
    BarControl.subtitles,
    BarControl.hide,
  },
);

const _tablet = RoomBarCaps(
  tablet: true,
  controls: {
    BarControl.mic,
    BarControl.camera,
    BarControl.react,
    BarControl.skipBack,
    BarControl.skipForward,
    BarControl.subtitles,
    BarControl.volume,
  },
);

RoomBarForm _pick(double slot, {RoomBarCaps caps = _phone, double scale = 1}) =>
    pickBarForm(slot: slot, caps: caps, scaler: TextScaler.linear(scale));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The thresholds are measured from the time labels, so they need the real
  // mono face (Ahem's square glyphs would make every label 11 px per char).
  setUpAll(() async {
    final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  group('phone ladder picks the first form whose width fits', () {
    final table = {
      900.0: RoomBarForm.f1,
      732.0: RoomBarForm.f1,
      560.0: RoomBarForm.f1,
      559.0: RoomBarForm.f2,
      492.0: RoomBarForm.f2,
      491.0: RoomBarForm.f3,
      442.0: RoomBarForm.f3,
      440.0: RoomBarForm.f3,
      439.0: RoomBarForm.f4,
      388.0: RoomBarForm.f4,
      387.0: RoomBarForm.f5,
      332.0: RoomBarForm.f5,
      // Under the floor the floor form is squeezed rather than dropped.
      300.0: RoomBarForm.f5,
    };
    for (final entry in table.entries) {
      test('${entry.key} -> ${entry.value.name}', () {
        expect(_pick(entry.key), entry.value);
      });
    }
  });

  group('touch tablet ladder skips F2', () {
    final table = {
      900.0: RoomBarForm.t0,
      580.0: RoomBarForm.t0,
      579.0: RoomBarForm.t1,
      470.0: RoomBarForm.t1,
      469.0: RoomBarForm.f3,
      440.0: RoomBarForm.f3,
      420.0: RoomBarForm.f4,
      340.0: RoomBarForm.f5,
    };
    for (final entry in table.entries) {
      test('${entry.key} -> ${entry.value.name}', () {
        expect(_pick(entry.key, caps: _tablet), entry.value);
      });
    }
  });

  test('larger text steps the ladder down earlier', () {
    // The icons never scale, but the time labels do (up to 1.3x), so the
    // one-row forms need more room and the same slot takes a later form.
    expect(_pick(492), RoomBarForm.f2);
    expect(_pick(492, scale: 2), isNot(RoomBarForm.f2));
    expect(
      thresholdOf(RoomBarForm.f2, _phone, const TextScaler.linear(2)),
      greaterThan(thresholdOf(RoomBarForm.f2, _phone, const TextScaler.linear(1))),
    );
    // ...and stops growing at 1.3x, so 2x is no worse than 1.3x.
    expect(
      thresholdOf(RoomBarForm.f2, _phone, const TextScaler.linear(2)),
      thresholdOf(RoomBarForm.f2, _phone, const TextScaler.linear(1.3)),
    );
  });

  test('media under an hour has narrower labels, so forms fit sooner', () {
    const short = RoomBarCaps(controls: {...BarControl.values}, hourLabels: false);
    expect(
      naturalWidth(RoomBarForm.f2, short, const TextScaler.linear(1)),
      lessThan(naturalWidth(RoomBarForm.f2, _phone, const TextScaler.linear(1))),
    );
  });

  group('what each form folds into More', () {
    test('F1 folds nothing', () => expect(RoomBarForm.f1.folded, isEmpty));
    test('F2: the source group, hide and the skips go together', () {
      expect(RoomBarForm.f2.folded.intersection(_phone.controls), {
        BarControl.hide,
        BarControl.source,
        BarControl.openFile,
        BarControl.audio,
        BarControl.subtitles,
        BarControl.skipBack,
        BarControl.skipForward,
      });
    });
    test('then react, then the camera, the mic last', () {
      expect(RoomBarForm.f3.folded, contains(BarControl.react));
      expect(RoomBarForm.f3.folded, isNot(contains(BarControl.camera)));
      expect(RoomBarForm.f4.folded, contains(BarControl.camera));
      expect(RoomBarForm.f4.folded, isNot(contains(BarControl.mic)));
      expect(RoomBarForm.f5.folded, contains(BarControl.mic));
    });
    test('seek and play have no BarControl: they can never fold', () {
      // The enum lists only the icons beside them; nothing names the scrubber
      // or the play key, so no form can fold them.
      for (final form in RoomBarForm.values) {
        expect(form.height, anyOf(112, 64));
      }
    });
    test('heights: F1 and the tablet forms are two rows, F2-F5 one', () {
      expect(RoomBarForm.f1.height, 112);
      expect(RoomBarForm.t0.twoRows, isTrue);
      expect(RoomBarForm.t1.twoRows, isTrue);
      for (final f in [RoomBarForm.f2, RoomBarForm.f3, RoomBarForm.f4, RoomBarForm.f5]) {
        expect(f.height, 64);
      }
    });
  });

  group('height is a second input: the facecam rail slot', () {
    test('tiles: 136x77 from a 210 px slot, else 104x58; count = floor((slot-44)/(tile+6))', () {
      expect(railPlanFor(172).large, isFalse);
      expect(railPlanFor(172).tiles, 2);
      expect(railPlanFor(209).large, isFalse);
      expect(railPlanFor(210).large, isTrue);
      expect(railPlanFor(210).tiles, 2);
      expect(railPlanFor(220).tiles, 2);
      expect(railPlanFor(157).tiles, 1);
      expect(railPlanFor(157).holdsTwo, isFalse);
      expect(railPlanFor(172).tileWidth, 104);
      expect(railPlanFor(220).tileWidth, 136);
    });

    test('the slot runs from y=72 to the bar top minus 12', () {
      expect(railSlotHeight(390, RoomBarForm.f1), 172); // board A
      expect(railSlotHeight(390, RoomBarForm.f3), 220); // board B
      expect(railSlotHeight(375, RoomBarForm.f1), 157);
      expect(railSlotHeight(375, RoomBarForm.f2), 205); // board C, D
    });

    test('the reserve follows the form: ~134 for F1, ~86 for F2-F5', () {
      expect(landscapeControlsReserve(RoomBarForm.f1), 134);
      for (final f in [RoomBarForm.f2, RoomBarForm.f3, RoomBarForm.f4, RoomBarForm.f5]) {
        expect(landscapeControlsReserve(f), 86);
      }
    });

    bool rail(double boxHeight, RoomBarForm f) =>
        railPlanFor(railSlotHeight(boxHeight, f)).holdsTwo;

    test(
      '667x375, chat closed: slot 555 would fit F1 but for the wider av gap, and F1 leaves one tile -> F2 (board C)',
      () {
        expect(
          pickBarForm(
            slot: 555,
            caps: _phone,
            scaler: TextScaler.noScaling,
            accepts: (f) => rail(375, f),
          ),
          RoomBarForm.f2,
        );
      },
    );

    test('844x390, chat closed: F1 leaves a 172 slot, two tiles -> F1 (board A)', () {
      expect(
        pickBarForm(
          slot: 732,
          caps: _phone,
          scaler: TextScaler.noScaling,
          accepts: (f) => rail(390, f),
        ),
        RoomBarForm.f1,
      );
    });

    test('844x390, chat open: slot 442 -> F3 with large tiles (board B)', () {
      final form = pickBarForm(
        slot: 442,
        caps: _phone,
        scaler: TextScaler.noScaling,
        accepts: (f) => rail(390, f),
      );
      expect(form, RoomBarForm.f3);
      final plan = railPlanFor(railSlotHeight(390, form));
      expect(plan.large, isTrue);
      expect(plan.tiles, 2);
    });

    test('667x375, chat open: slot 332 -> F5 with two small tiles (board D)', () {
      final form = pickBarForm(
        slot: 332,
        caps: _phone,
        scaler: TextScaler.noScaling,
        accepts: (f) => rail(375, f),
      );
      expect(form, RoomBarForm.f5);
      final plan = railPlanFor(railSlotHeight(375, form));
      expect(plan.large, isFalse);
      expect(plan.tiles, 2);
    });

    test('when no form leaves a rail of two, the shortest that fits wins', () {
      final form = pickBarForm(
        slot: 900,
        caps: _phone,
        scaler: TextScaler.noScaling,
        accepts: (_) => false,
      );
      expect(form, RoomBarForm.f2);
    });
  });

  group('chat beside the bar', () {
    test('width = min(300, 38%, safe - 12 - 332), never under 180', () {
      expect(landscapeChatWidth(732), closeTo(278.16, 0.01)); // board B
      expect(landscapeChatWidth(555), closeTo(210.9, 0.01)); // board D
      expect(landscapeChatWidth(1000), 300);
      expect(landscapeChatWidth(524), 180);
      expect(landscapeChatWidth(400), 180);
    });

    test('the bar keeps at least its 332 floor whenever the chat fits at all', () {
      for (var w = 524.0; w <= 1200; w += 7) {
        expect(w - 12 - landscapeChatWidth(w), greaterThanOrEqualTo(kBarSlotFloor - 0.01));
      }
    });

    test('under 524 a chat column and the bar cannot both fit', () {
      expect(landscapeChatFits(524), isTrue);
      expect(landscapeChatFits(523), isFalse);
    });
  });
}
