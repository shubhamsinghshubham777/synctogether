// The room control bar's space-driven collapse (board 46), drawn for real: which
// controls each width keeps inline, what the More list holds, and that the seek
// bar and play/pause survive every width at every text scale.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/widgets/room_control_bar.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/inputs.dart';
import 'package:synctogether/ui/pt_theme.dart';

class _Taps {
  final log = <String>[];
}

Widget _bar(
  double width, {
  bool compact = true,
  bool docked = false,
  bool micOn = false,
  bool camOn = false,
  bool secondary = true,
  double textScale = 1,
  _Taps? taps,
}) {
  final t = taps ?? _Taps();
  void tap(String name) => t.log.add(name);
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      backgroundColor: PTColors.canvas,
      body: Align(
        alignment: Alignment.bottomLeft,
        child: SizedBox(
          width: width,
          child: RoomControlBar(
            playing: true,
            position: const Duration(minutes: 42, seconds: 8),
            duration: const Duration(hours: 2, minutes: 49, seconds: 3),
            volume: 0.7,
            micOn: micOn,
            camOn: camOn,
            avAvailable: true,
            camAvailable: true,
            compact: compact,
            docked: docked,
            subtitleTag: 'EN',
            audioTag: 'JA 5.1',
            sourceTag: 'Local file',
            actions: RoomControlBarActions(
              onPlayPause: () => tap('play'),
              onSeek: (_) => tap('seek'),
              onSkip: (d) => tap('skip ${d.inSeconds}'),
              onMicToggle: (v) => tap('mic $v'),
              onCamToggle: (v) => tap('cam $v'),
              onAudioTracks: secondary ? () => tap('audio') : null,
              onSubtitles: secondary ? () => tap('subs') : null,
              onSwitchSource: secondary && compact ? () => tap('source') : null,
              onOpenFile: secondary && compact ? () => tap('file') : null,
              onVolume: (_) {},
              onToggleMute: () => tap('mute'),
              onReact: () => tap('react'),
              onHideControls: compact ? () => tap('hide') : null,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget bar, {
  TargetPlatform platform = TargetPlatform.android,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view
    ..physicalSize = const Size(1400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(bar);
  await tester.pump(const Duration(milliseconds: 400));
}

Finder get _more => find.byIcon(BoothIcons.moreHoriz).hitTestable();

Finder _tip(String tooltip) => find.byTooltip(tooltip).hitTestable();

void _test(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

/// The rows the board lists for each form, in its fixed order.
const _all = [
  'Microphone',
  'Camera',
  'React',
  'Back 10 s',
  'Forward 10 s',
  'Source',
  'Open file',
  'Audio track',
  'Subtitles',
  'Hide controls',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('phone bar: the form each width picks', () {
    // width -> (form, labels folded into More)
    final forms = <double, (String, List<String>)>{
      600: ('F1', const []),
      560: ('F1', const []),
      520: ('F2', _all.sublist(3)),
      492: ('F2', _all.sublist(3)),
      460: ('F3', _all.sublist(2)),
      440: ('F3', _all.sublist(2)),
      410: ('F4', _all.sublist(1)),
      388: ('F4', _all.sublist(1)),
      360: ('F5', _all),
      332: ('F5', _all),
    };
    for (final entry in forms.entries) {
      final (form, folded) = entry.value;
      _test('${entry.key} is $form', (tester) async {
        await _pump(tester, _bar(entry.key));
        final inline = {
          'Microphone': _tip('Mic on (D)'),
          'Camera': _tip('Camera on (E)'),
          'React': _tip('React (R)'),
          'Back 10 s': _tip('Back 10 seconds'),
          'Forward 10 s': _tip('Forward 10 seconds'),
          'Source': _tip('Switch source'),
          'Open file': _tip('Open file'),
          'Audio track': _tip('Audio track'),
          'Subtitles': _tip('Subtitles'),
          'Hide controls': _tip('Hide controls (H)'),
        };
        for (final label in _all) {
          expect(
            inline[label],
            folded.contains(label) ? findsNothing : findsOneWidget,
            reason: '$label at ${entry.key} ($form)',
          );
        }
        // More only exists when something folded.
        expect(_more, folded.isEmpty ? findsNothing : findsOneWidget);
        // The seek bar, both time labels and play/pause never fold.
        expect(find.byType(PTSlider).hitTestable(), findsOneWidget);
        expect(find.byType(PTPlayButton).hitTestable(), findsOneWidget);
        expect(find.text('42:08'), findsOneWidget);
        expect(find.text('2:49:03'), findsOneWidget);
        // Forms are picked, not scaled: every key stays 44 and play 52.
        expect(tester.getSize(find.byType(PTPlayButton)).width, 52);
        if (folded.isNotEmpty) {
          final button = find.ancestor(of: _more, matching: find.byType(PTIconButton)).first;
          expect(tester.getSize(button).width, 44);
        }
        // Heights: two rows 112, one row 64.
        expect(tester.getSize(find.byType(RoomControlBar)).height, form == 'F1' ? 112 : 64);
      });
    }

    _test('More lists exactly what folded, in the fixed order, with the value under the name', (
      tester,
    ) async {
      final taps = _Taps();
      await _pump(tester, _bar(332, taps: taps));
      final moreRight = tester.getRect(find.byIcon(BoothIcons.moreHoriz)).right;
      await tester.tap(_more);
      await tester.pump(const Duration(milliseconds: 400));
      var previousTop = -1.0;
      for (final label in _all) {
        final text = find.text(label);
        expect(text, findsOneWidget, reason: label);
        final row = find.ancestor(of: text, matching: find.byType(AnimatedContainer)).first;
        expect(tester.getSize(row).height, greaterThanOrEqualTo(44), reason: '$label cell');
      }
      // Values sit under the names.
      for (final entry in {
        'Microphone': 'Off',
        'Camera': 'Off',
        'React': 'Open strip',
        'Back 10 s': 'Same as double-tap',
        'Source': 'Local file',
        'Audio track': 'JA 5.1',
        'Subtitles': 'EN',
        'Hide controls': 'Tap to bring back',
      }.entries) {
        final cell = find.ancestor(of: find.text(entry.key), matching: find.byType(Row)).first;
        final value = find.descendant(of: cell, matching: find.text(entry.value));
        expect(value, findsOneWidget, reason: entry.key);
        expect(
          tester.getRect(value).top,
          greaterThanOrEqualTo(tester.getRect(find.text(entry.key)).bottom - 1),
          reason: entry.key,
        );
      }
      // Two columns past five rows, filled top to bottom: five and five.
      final xs = [for (final l in _all) tester.getTopLeft(find.text(l)).dx];
      expect(xs.take(5).toSet().length, 1);
      expect(xs.skip(5).toSet().length, 1);
      expect(xs[5], greaterThan(xs[0]));
      for (final l in _all.take(5)) {
        final top = tester.getTopLeft(find.text(l)).dy;
        expect(top, greaterThan(previousTop));
        previousTop = top;
      }
      // Anchored above the bar, inside the screen, right-aligned to the button.
      final panel = tester.getRect(
        find.ancestor(of: find.text('Source'), matching: find.byType(Container)).last,
      );
      final bar = tester.getRect(find.byType(RoomControlBar));
      expect(panel.bottom, lessThanOrEqualTo(bar.top));
      expect(panel.top, greaterThanOrEqualTo(16));
      expect(panel.left, greaterThanOrEqualTo(12));
      expect(panel.right, lessThanOrEqualTo(1400 - 12));
      expect(moreRight, greaterThan(0));
      // A row does what its inline key does, and closes the list.
      await tester.tap(find.text('Back 10 s'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps.log, ['skip -10']);
      expect(find.text('Source'), findsNothing);
    });

    _test('F3 lists eight rows in two columns of four', (tester) async {
      await _pump(tester, _bar(450));
      await tester.tap(_more);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Microphone'), findsNothing);
      expect(find.text('Camera'), findsNothing);
      for (final label in _all.sublist(2)) {
        expect(find.text(label), findsOneWidget);
      }
      final xs = [for (final l in _all.sublist(2)) tester.getTopLeft(find.text(l)).dx];
      expect(xs.take(4).toSet().length, 1);
      expect(xs.skip(4).toSet().length, 1);
      expect(xs[4], greaterThan(xs[0]));
    });

    _test('a coral dot on More when the mic or camera is live while folded', (tester) async {
      Finder dot() => find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == PTColors.ember &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      await _pump(tester, _bar(332));
      expect(dot(), findsNothing);
      await _pump(tester, _bar(332, micOn: true));
      expect(dot(), findsOneWidget);
      // Camera live but still inline (F3 keeps it): no dot, the key shows it.
      await _pump(tester, _bar(450, camOn: true));
      expect(dot(), findsNothing);
      // ...and folded again at F5.
      await _pump(tester, _bar(340, camOn: true));
      expect(dot(), findsOneWidget);
    });

    _test('a hot mic row says On air and toggles it off', (tester) async {
      final taps = _Taps();
      await _pump(tester, _bar(332, micOn: true, taps: taps));
      await tester.tap(_more);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('On air'), findsOneWidget);
      await tester.tap(find.text('Microphone'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps.log, ['mic false']);
    });
  });

  group('seek bar and play/pause at every width and text scale', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final compact in [true, false]) {
        _test('${compact ? 'phone' : 'tablet floating'} bar, text x$scale, 300-900 px', (
          tester,
        ) async {
          for (var w = 300.0; w <= 900; w += 20) {
            await _pump(tester, _bar(w, compact: compact, textScale: scale));
            expect(find.byType(PTSlider).hitTestable(), findsAtLeastNWidgets(1), reason: 'seek $w');
            expect(find.byType(PTPlayButton).hitTestable(), findsOneWidget, reason: 'play $w');
            expect(tester.getSize(find.byType(PTPlayButton)).width, 52);
            final bar = tester.getRect(find.byType(RoomControlBar));
            expect(bar.width, closeTo(w, 0.01));
            for (final f in [find.byType(PTPlayButton), find.byType(PTSlider).first]) {
              final r = tester.getRect(f);
              expect(
                r.left >= bar.left - 0.5 && r.right <= bar.right + 0.5,
                isTrue,
                reason: 'x$scale at $w: $r outside $bar',
              );
            }
            expect(tester.takeException(), isNull, reason: 'overflow at $w x$scale');
          }
        });
      }
    }
  });

  group('touch tablet floating bar: T0, T1, then F3-F5', () {
    Finder slider() => find.descendant(
      of: find.byType(RoomControlBar),
      matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 90),
    );

    _test('T0 (>= 580): two rows with the SUBS key and the volume slider', (tester) async {
      await _pump(tester, _bar(600, compact: false));
      expect(tester.getSize(find.byType(RoomControlBar)).height, 112);
      expect(find.text('SUBS · EN').hitTestable(), findsOneWidget);
      expect(slider(), findsOneWidget);
      expect(_tip('Mute (M)'), findsOneWidget);
      expect(_more, findsNothing);
    });

    _test('T1 (470-580): the slider folds to the glyph, the SUBS key stays', (tester) async {
      await _pump(tester, _bar(500, compact: false));
      expect(tester.getSize(find.byType(RoomControlBar)).height, 112);
      expect(find.text('SUBS · EN').hitTestable(), findsOneWidget);
      expect(slider(), findsNothing);
      expect(_tip('Mute (M)'), findsOneWidget);
      expect(_more, findsNothing);
    });

    _test('below 470 it continues as F3/F4/F5 and the SUBS key and volume go to More', (
      tester,
    ) async {
      await _pump(tester, _bar(450, compact: false));
      expect(tester.getSize(find.byType(RoomControlBar)).height, 64);
      expect(find.text('SUBS · EN').hitTestable(), findsNothing);
      expect(_tip('Mute (M)'), findsNothing);
      expect(_more, findsOneWidget);
      await tester.tap(_more);
      await tester.pump(const Duration(milliseconds: 400));
      for (final label in ['React', 'Back 10 s', 'Forward 10 s', 'Subtitles', 'Volume']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // A tablet has no source group of its own.
      expect(find.text('Source'), findsNothing);
      expect(find.text('Hide controls'), findsNothing);
    });

    _test('no 36 px keys and no FittedBox scaling in the floating bar', (tester) async {
      await _pump(tester, _bar(600, compact: false));
      expect(
        find.descendant(of: find.byType(RoomControlBar), matching: find.byType(FittedBox)),
        findsNothing,
      );
      for (final tooltip in ['Mic on (D)', 'React (R)']) {
        expect(tester.getSize(find.byTooltip(tooltip)).width, 44);
      }
    });
  });

  group('desktop docked bar folds before it scales', () {
    _test('wide: AUDIO, SUBS and the slider are inline', (tester) async {
      await _pump(tester, _bar(1000, compact: false, docked: true), platform: TargetPlatform.macOS);
      expect(find.text('AUDIO · JA 5.1').hitTestable(), findsOneWidget);
      expect(find.text('SUBS · EN').hitTestable(), findsOneWidget);
      expect(_more, findsNothing);
      expect(
        find.descendant(of: find.byType(RoomControlBar), matching: find.byType(FittedBox)),
        findsNothing,
      );
    });

    _test('narrower: AUDIO folds first, then SUBS, then the volume; keys keep their size', (
      tester,
    ) async {
      var seenAudioFold = false;
      var seenSubsFold = false;
      for (final w in [900.0, 760.0, 700.0, 640.0, 600.0, 560.0]) {
        await _pump(tester, _bar(w, compact: false, docked: true), platform: TargetPlatform.macOS);
        final audio = find.text('AUDIO · JA 5.1').hitTestable().evaluate().isNotEmpty;
        final subs = find.text('SUBS · EN').hitTestable().evaluate().isNotEmpty;
        if (!audio) seenAudioFold = true;
        if (!subs) seenSubsFold = true;
        // SUBS never folds before AUDIO.
        if (subs == false) expect(audio, isFalse, reason: 'SUBS folded before AUDIO at $w');
        expect(
          find.descendant(of: find.byType(RoomControlBar), matching: find.byType(FittedBox)),
          findsNothing,
          reason: 'scaled at $w',
        );
        expect(tester.getSize(find.byTooltip('Mic on (D)')).width, 40);
        expect(tester.takeException(), isNull, reason: 'overflow at $w');
      }
      expect(seenAudioFold, isTrue);
      expect(seenSubsFold, isTrue);
    });
  });
}
