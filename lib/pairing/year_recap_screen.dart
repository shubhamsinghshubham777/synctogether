import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/rendering.dart';
import 'package:saf_stream/saf_stream.dart';

import '../analytics.dart';
import '../diagnostics.dart';
import '../platform.dart';
import '../profile/profile_service.dart';
import '../ui/banners.dart';
import '../ui/booth_icons.g.dart';
import '../ui/buttons.dart';
import '../ui/loader.dart';
import '../ui/pt_theme.dart';
import 'pair_logic.dart';
import 'pair_models.dart';
import 'pair_page.dart';
import 'pair_service.dart';
import 'pair_share.dart';
import 'pair_widgets.dart';

/// "Our year": one card, stats only - no titles, no chat - sized 4:5 for a story
/// or a chat, with the wordmark on it. Safe to share by construction.
/// How wide the card may be shown. Wider than its 340 design points so a desktop window is
/// not left mostly empty, capped so it never swallows the screen.
const _kCardMaxWidth = 520.0;

class YearRecapScreen extends StatefulWidget {
  const YearRecapScreen({super.key});

  @override
  State<YearRecapScreen> createState() => _YearRecapScreenState();
}

class _YearRecapScreenState extends State<YearRecapScreen> {
  final _boundary = GlobalKey();
  PairStats? _stats;
  Set<int> _months = const {};
  int _year = DateTime.now().year;
  bool _sharing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final now = DateTime.now();
    var year = now.year;
    var stats = await PairService.instance.loadStatsForYear(year);
    // In January the new year has nothing in it yet: show the one just finished.
    final recap = recapYear(now, thisYearHasNights: stats.nights > 0);
    if (recap != year) {
      year = recap;
      stats = await PairService.instance.loadStatsForYear(year);
    }
    var months = <int>{};
    try {
      months = watchedMonths(await PairService.instance.exportHistory(), year);
    } catch (e, s) {
      // The strip is decoration; the card still shows without it.
      reportNonFatal(e, s, during: 'loading the months for the year card');
    }
    if (mounted) {
      setState(() {
        _months = months;
        _stats = stats;
        _year = year;
      });
    }
  }

  /// The card as a PNG at 3x its design size, or null if it is not on screen.
  Future<Uint8List?> _capture() async {
    final render = _boundary.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary) return null;
    final image = await render.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _share(BuildContext buttonContext) async {
    setState(() => _sharing = true);
    try {
      final bytes = await _capture();
      if (bytes == null || !buttonContext.mounted) return;
      final shared = await shareBytes(
        buttonContext,
        bytes: bytes,
        name: 'our-year-$_year.png',
        mimeType: 'image/png',
      );
      if (shared) Analytics.instance.track('pair_year_shared');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Desktop: a save dialog. Android: pick a folder through the system's own document picker
  /// and write the picture into it - no storage permission is asked for, the folder grant is
  /// the user's choice for that one save. (iOS's share sheet already has "Save Image".)
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bytes = await _capture();
      if (bytes == null) return;
      final name = 'our-year-$_year.png';
      if (_isAndroid) {
        final folder = await FastFilePicker.pickFolder(writePermission: true);
        final uri = folder?.uri;
        if (uri == null) return;
        await SafStream().writeFileBytes(uri, name, 'image/png', bytes, overwrite: false);
      } else {
        final where = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'PNG image', extensions: ['png'], mimeTypes: ['image/png']),
          ],
        );
        if (where == null) return;
        await XFile.fromData(bytes, mimeType: 'image/png', name: name).saveTo(where.path);
      }
      trace('year card saved', category: 'media', data: {'platform': defaultTargetPlatform.name});
      if (mounted) showPTSnack(context, 'Saved.', kind: .success);
    } catch (e, st) {
      reportNonFatal(e, st, during: 'saving the year card');
      if (mounted) showPTSnack(context, "Couldn't save just now. Try again.", kind: .error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final pair = PairService.instance.pair;
    final me = ProfileService.instance.profile;
    if (stats == null || pair == null) {
      return const PairPage(
        title: 'Our year',
        children: [
          Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: PTLoader()),
          ),
        ],
      );
    }
    final mine = (me?.displayName ?? 'You').split(' ').first;
    final theirs = pair.partner.displayName.split(' ').first;
    final apart = shouldShowPartnerTime(pair.partner.timezone, DateTime.now())
        ? '${cityOfZone(pair.partner.timezone)} · ${offsetLabel(offsetFromMe(pair.partner.timezone, DateTime.now())!).replaceAll(' behind', '').replaceAll(' ahead', '')} apart'
        : null;

    return PairPage(
      title: 'Our year',
      spacing: 16,
      children: [
        // The card is drawn at its fixed design size and only *shown* scaled to the space,
        // so the exported image is the same 1020 x 1275 whatever screen it came from.
        LayoutBuilder(
          builder: (context, box) {
            // Also limited by the window's height, so the card and its buttons fit together
            // in a short window instead of pushing the buttons below the fold.
            final byHeight =
                (MediaQuery.sizeOf(context).height - 300) * _YearCard._w / _YearCard._h;
            final cap = byHeight.clamp(280.0, _kCardMaxWidth);
            final width = box.maxWidth < cap ? box.maxWidth : cap;
            return Center(
              child: SizedBox(
                width: width,
                height: width * _YearCard._h / _YearCard._w,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: RepaintBoundary(
                    key: _boundary,
                    child: _YearCard(
                      year: _year,
                      mine: mine,
                      theirs: theirs,
                      apart: apart,
                      stats: stats,
                      months: _months,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: Builder(
                builder: (buttonContext) => PTButton(
                  label: 'Share image',
                  icon: BoothIcons.share,
                  loading: _sharing,
                  onPressed: stats.nights == 0 ? null : () => _share(buttonContext),
                ),
              ),
            ),
            if (isDesktop || _isAndroid)
              Expanded(
                child: PTButton(
                  label: 'Save',
                  variant: .secondary,
                  loading: _saving,
                  onPressed: stats.nights == 0 ? null : _save,
                ),
              ),
          ],
        ),
        PairNote(
          stats.nights == 0
              ? 'Spend a night together and this fills in.'
              : '$theirs can share their own copy. Stats only: no film titles, no chat.',
          center: true,
        ),
      ],
    );
  }
}

class _YearCard extends StatelessWidget {
  static const _w = 340.0;
  static const _h = 425.0;
  // Width the film strip takes from the right edge, so no text ever touches it.
  static const _stripRoom = 22.0;

  // Past this many characters the two names go on two lines.
  static const _oneLineNames = 22;

  const _YearCard({
    required this.year,
    required this.mine,
    required this.theirs,
    required this.apart,
    required this.stats,
    required this.months,
  });

  final int year;
  final String mine;
  final String theirs;
  final String? apart;
  final PairStats stats;
  final Set<int> months;

  /// "Maya & Sam" on one line, scaled down to fit. A long pair ("Bartholomew... & Wolfe...")
  /// would shrink past reading on one line, so it breaks after the ampersand and each name
  /// gets the full width.
  Widget _names() {
    Widget line(String text) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(text, maxLines: 1, style: PTText.display.copyWith(fontSize: 38, height: 0.95)),
    );
    if ('$mine & $theirs'.length <= _oneLineNames) return line('$mine & $theirs');
    return Column(
      crossAxisAlignment: .start,
      spacing: 2,
      children: [line('$mine &'), line(theirs)],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The card is an image people share, so it is drawn at one fixed design size
    // with text scaling off - it must look the same for everyone who sends it,
    // however large their system text is - and scaled down to fit the screen.
    return SizedBox(
      width: _w,
      height: _h,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Container(
          decoration: BoxDecoration(
            color: PTColors.canvas,
            borderRadius: BorderRadius.circular(PTRadius.panel),
            border: Border.all(color: PTColors.rail),
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(
            painter: _BoothPainter(months),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 26, 26 + _stripRoom, 26),
              child: Column(
                crossAxisAlignment: .start,
                spacing: 14,
                children: [
                  Text(
                    'OUR YEAR · $year',
                    style: PTText.label.copyWith(color: PTColors.primary, letterSpacing: 2),
                  ),
                  _names(),
                  if (apart != null)
                    Row(
                      spacing: 8,
                      children: [
                        const Icon(BoothIcons.globe, size: 16, color: PTColors.fgDim),
                        Expanded(
                          child: Text(
                            apart!,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: PTText.caption.copyWith(color: PTColors.fgSoft),
                          ),
                        ),
                      ],
                    ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      hoursLabel(stats.hours),
                      style: PTText.display.copyWith(
                        fontSize: 84,
                        height: 0.9,
                        color: PTColors.streak,
                      ),
                    ),
                  ),
                  Text(
                    'hours watching the same screen',
                    style: PTText.body.copyWith(fontSize: 15, color: PTColors.fgDim),
                  ),
                  const Divider(height: 1, color: PTColors.rail),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final t in [
                        countLabel(stats.nights, 'Night'),
                        countLabel(stats.films, 'Film'),
                        '${stats.bestStreakWeeks} WK STREAK',
                      ])
                        Text(
                          t,
                          style: PTText.mono.copyWith(fontSize: 10.5, color: PTColors.fgSoft),
                        ),
                    ],
                  ),
                  Text(
                    'sync·together',
                    style: PTText.cardHeading.copyWith(fontSize: 14, color: PTColors.fgMute),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's backdrop: a projector beam off the top-left corner (two flat, hard-edged
/// wedges - no gradient) and a film strip down the right edge, one frame per month,
/// Beam-filled for each month the pair watched together.
class _BoothPainter extends CustomPainter {
  const _BoothPainter(this.months);

  final Set<int> months;

  @override
  void paint(Canvas canvas, Size size) {
    final wide = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.62, 0)
      ..lineTo(0, size.height * 0.5)
      ..close();
    final narrow = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.34, 0)
      ..lineTo(0, size.height * 0.27)
      ..close();
    canvas.drawPath(wide, Paint()..color = PTColors.primary.withValues(alpha: 0.07));
    canvas.drawPath(narrow, Paint()..color = PTColors.primary.withValues(alpha: 0.08));

    const stripW = 14.0;
    const frames = 12;
    final left = size.width - stripW - 12;
    const top = 26.0;
    final span = size.height - top * 2;
    final slot = span / frames;
    final line = Paint()
      ..color = PTColors.rail
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final hole = Paint()..color = PTColors.rail;
    for (var i = 0; i < frames; i++) {
      final y = top + i * slot;
      final frame = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, y + 2, stripW, slot - 4),
        const Radius.circular(2),
      );
      if (months.contains(i + 1)) {
        canvas.drawRRect(frame, Paint()..color = PTColors.primary);
      } else {
        canvas.drawRRect(frame, line);
      }
      for (final dx in [left - 5, left + stripW + 3]) {
        canvas.drawCircle(Offset(dx, y + slot / 2), 1.2, hole);
      }
    }
  }

  @override
  bool shouldRepaint(_BoothPainter old) =>
      old.months.length != months.length || old.months != months;
}
