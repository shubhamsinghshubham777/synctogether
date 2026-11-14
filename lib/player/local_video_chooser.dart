// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/player/media_file_types.dart';
import 'package:synctogether/player/photo_picker.dart';
import 'package:synctogether/player/recent_format.dart';
import 'package:synctogether/player/recent_videos.dart';
import 'package:synctogether/ui/booth_icons.g.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

// The local-video chooser (canvas board 47): ONE place every "pick a video from
// this device" button opens, so Photos, Files and Recent behave the same in the
// room, the lobby and the empty-room card.
//
//   final choice = await showLocalVideoChooser(context);
//   if (choice == null) return;            // closed
//   choice.video                           // a ready LocalVideo; the CALLER owns release()
//   choice.source                          // photos / files / recent
//
// The chooser does everything up to "a file we can open": runs the picker,
// refuses plainly-not-video picks (the banner keeps the chooser open), adopts
// the pick (security scope / SAF grant), waits for an iCloud download, and for a
// Recent row resolves its reference. It does NOT record anything - the caller
// does that once the player has really opened the file (`RecentVideos.record`).
//
// Form follows the board and the layout class: a bottom sheet under 480 wide
// (stacked entry rows), a dialog with side-by-side entry tiles on a tablet, a
// Files-only dialog on desktop (no Photos row), and a two-pane panel in phone
// landscape (entries left, the shelf scrolling right). A shelf that is long
// scrolls with the body; entries never fold into a menu.

/// Where the chosen video came from.
enum ChoiceSource { photos, files, recent }

class LocalVideoChoice {
  const LocalVideoChoice(this.video, this.source);

  /// Ready to play. Whoever receives this calls `video.release()` when the file
  /// is replaced or the room is left.
  final LocalVideo video;
  final ChoiceSource source;
}

/// Product event for "a person picked a local video", by door. The source only,
/// never a name or a path (see the Analytics section of docs/agent/ui-and-av.md).
/// Called from the places a human tapped; never from a remote or gate path.
void trackLocalVideoChosen(ChoiceSource source) =>
    Analytics.instance.track('local_video_chosen', {'source': source.name});

typedef FilePick = Future<FastFilePickerPath?> Function();

Future<FastFilePickerPath?> _pickFromFiles() =>
    FastFilePicker.pickFile(acceptedTypeGroups: kVideoPickerGroups);

/// Everything the chooser touches outside the widget tree. Pure delegation to
/// the real services by default; tests hand in fakes.
class LocalVideoChooserServices {
  LocalVideoChooserServices({
    LocalVideoAccess? access,
    RecentVideos? recents,
    FilePick? pickFile,
    PickPhotoVideo? pickPhoto,
    bool? showPhotos,
    bool? probeMissing,
    DateTime Function()? clock,
  }) : access = access ?? LocalVideoAccess.instance,
       recents = recents ?? RecentVideos.instance,
       pickFile = pickFile ?? _pickFromFiles,
       pickPhoto = pickPhoto ?? pickPhotoVideo,
       showPhotos = showPhotos ?? photosAvailable,
       // A plain path is cheap to probe and has no side effects. Bookmarks and
       // content URIs are not: resolving one starts access that must be
       // released, so they are only tried when the person taps the row.
       probeMissing = probeMissing ?? isDesktop,
       clock = clock ?? DateTime.now;

  final LocalVideoAccess access;
  final RecentVideos recents;
  final FilePick pickFile;
  final PickPhotoVideo pickPhoto;

  /// The "From Photos" entry: touch platforms only.
  final bool showPhotos;
  final bool probeMissing;
  final DateTime Function() clock;
}

/// Opens the chooser: a bottom sheet under 480 wide, a dialog otherwise (a wider
/// one in phone landscape, for the two-pane form).
Future<LocalVideoChoice?> showLocalVideoChooser(
  BuildContext context, {
  LocalVideoChooserServices? services,
  ChoiceSource? autoStart,
}) {
  final svc = services ?? LocalVideoChooserServices();
  final size = MediaQuery.sizeOf(context);
  final sheet = size.width < kGlassSheetBreakpoint;
  return showGlassDialog<LocalVideoChoice>(
    context: context,
    width: _isLandscapePanel(size) ? 720 : 480,
    sheetOnCompact: true,
    padding: sheet
        ? const EdgeInsets.fromLTRB(20, 10, 20, 20)
        : const EdgeInsets.fromLTRB(24, 26, 24, 24),
    builder: (_) => LocalVideoChooser(services: svc, autoStart: autoStart),
  );
}

/// Phone landscape: too short for a stacked column, wide enough for two panes.
bool _isLandscapePanel(Size size) => size.height < 500 && size.width >= 560;

enum _Door { none, photos, files, recent }

class LocalVideoChooser extends StatefulWidget {
  const LocalVideoChooser({super.key, required this.services, this.autoStart});

  final LocalVideoChooserServices services;

  /// Opens straight onto one picker (the tablet empty room's own Photos and
  /// Files buttons); cancelling it leaves the chooser showing.
  final ChoiceSource? autoStart;

  @override
  State<LocalVideoChooser> createState() => _LocalVideoChooserState();
}

class _LocalVideoChooserState extends State<LocalVideoChooser> {
  LocalVideoChooserServices get _svc => widget.services;

  List<RecentVideo>? _entries;
  final _unavailable = <String, UnavailableReason>{};
  _Door _door = _Door.none;
  String? _busyId;
  String? _downloading;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _svc.recents.addListener(_reload);
    _reload();
    final door = widget.autoStart;
    if (door != null && door != ChoiceSource.recent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(door == ChoiceSource.photos ? _pickPhotos() : _pickFiles());
      });
    }
  }

  @override
  void dispose() {
    _svc.recents.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await _svc.recents.list();
    if (!mounted) return;
    if (_svc.probeMissing) {
      for (final e in list) {
        final ref = e.reference;
        if (ref is PathReference && !File(ref.path).existsSync()) {
          _unavailable[e.id] = UnavailableReason.missing;
        }
      }
    }
    setState(() => _entries = list);
  }

  bool get _busy => _door != _Door.none;

  void _close() => Navigator.of(context).maybePop();

  Future<void> _pickPhotos() async {
    if (_busy) return;
    setState(() {
      _door = _Door.photos;
      _notice = null;
    });
    PhotoPick? pick;
    try {
      pick = await _svc.pickPhoto();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'opening the photo picker');
      _fail("Hmm, Photos didn't open. Give it another go.");
      return;
    }
    if (!mounted) return;
    if (pick == null) return _idle();
    final r = await _svc.access.adoptPick(
      pickerName: pick.name,
      path: pick.path,
      uri: pick.uri,
      origin: VideoOrigin.photos,
    );
    await _finish(r, ChoiceSource.photos);
  }

  Future<void> _pickFiles({RecentVideo? replacing}) async {
    if (_busy) return;
    setState(() {
      _door = _Door.files;
      _notice = null;
    });
    FastFilePickerPath? picked;
    try {
      picked = await _svc.pickFile();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'opening the file picker');
      _fail("Hmm, the file picker didn't open. Give it another go.");
      return;
    }
    if (!mounted) return;
    if (picked == null || (picked.path == null && picked.uri == null)) return _idle();
    final name = displayNameFor(pickerName: picked.name, path: picked.path, uri: picked.uri);
    // The picker's filter is advisory (iOS Browse shows everything), so this is
    // the gate: refuse a plain non-video and keep the chooser open.
    if (refuseNonMedia(name)) return _fail(kNotAVideoMessage);
    final r = await _svc.access.adopt(picked);
    await _finish(r, ChoiceSource.files, replacing: replacing);
  }

  Future<void> _openRecent(RecentVideo e) async {
    if (_busy) return;
    setState(() {
      _door = _Door.recent;
      _busyId = e.id;
      _notice = null;
      _unavailable.remove(e.id);
    });
    final ResolveResult r;
    try {
      r = await _svc.recents.resolve(e);
    } catch (err, s) {
      reportNonFatal(err, s, during: 'reopening a recent video');
      return _fail("Hmm, that video won't open right now. Give it another go.");
    }
    await _finish(r, ChoiceSource.recent, row: e);
  }

  /// Everything after a pick resolved: wait out an iCloud download, then either
  /// hand the ready video back or say why not, in the row or in the banner.
  Future<void> _finish(
    ResolveResult first,
    ChoiceSource source, {
    RecentVideo? row,
    RecentVideo? replacing,
  }) async {
    var r = first;
    if (r.status == ResolveStatus.downloading) {
      if (mounted) setState(() => _downloading = r.video?.name);
      r = await _svc.access.waitForDownload(r);
      if (mounted) setState(() => _downloading = null);
    }
    final video = r.video;
    if (!r.isReady || video == null) {
      if (!mounted) return;
      setState(() {
        _door = _Door.none;
        _busyId = null;
        final reason = r.reason;
        if (row != null && reason != null) _unavailable[row.id] = reason;
        if (row == null || reason == null) _notice = r.message ?? kNotAVideoMessage;
      });
      return;
    }
    if (!mounted) {
      // Closed while it was opening: nobody is left to own the handle.
      await video.release();
      return;
    }
    if (replacing != null) {
      await _svc.recents.remove(replacing.id);
      if (!mounted) {
        await video.release();
        return;
      }
    }
    trace(
      'local video chosen',
      category: 'media',
      data: {'source': source.name, 'file': video.name},
    );
    trackLocalVideoChosen(source);
    Navigator.of(context).pop(LocalVideoChoice(video, source));
  }

  void _idle() => setState(() {
    _door = _Door.none;
    _busyId = null;
  });

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _door = _Door.none;
      _busyId = null;
      _notice = message;
    });
  }

  Future<void> _locate(RecentVideo e) => _pickFiles(replacing: e);

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return LayoutBuilder(
      builder: (context, box) {
        final twoPane = box.maxWidth >= 520 && height < 500;
        final tiles = !twoPane && _svc.showPhotos && box.maxWidth >= 400;
        final header = GlassDialogHeader(
          eyebrow: 'Local file',
          title: 'Choose a video',
          closeIconSize: 20,
          onClose: _close,
        );
        final notice = _notice == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 14),
                child: PTEntrance(
                  key: ValueKey(_notice),
                  duration: PTMotion.state,
                  offset: -6,
                  child: _Notice(
                    message: _notice!,
                    onDismiss: () => setState(() => _notice = null),
                  ),
                ),
              );
        final entries = _Entries(
          photos: _svc.showPhotos,
          tiles: tiles,
          compact: twoPane,
          busyDoor: _door,
          onPhotos: _pickPhotos,
          onFiles: _pickFiles,
        );
        final shelf = _Shelf(
          entries: _entries,
          unavailable: _unavailable,
          busyId: _busyId,
          downloading: _downloading,
          compact: twoPane,
          now: _svc.clock(),
          recents: _svc.recents,
          listHeight: twoPane ? _shelfHeight(context) : null,
          onOpen: _openRecent,
          onRemove: (e) => _svc.recents.remove(e.id),
          onLocate: _locate,
          onClear: () => _svc.recents.clear(),
        );
        if (twoPane) {
          return Row(
            crossAxisAlignment: .start,
            spacing: 20,
            children: [
              SizedBox(
                width: 268,
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  children: [header, ?notice, const SizedBox(height: 12), entries],
                ),
              ),
              Expanded(child: shelf),
            ],
          );
        }
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            header,
            ?notice,
            const SizedBox(height: 14),
            entries,
            const SizedBox(height: 14),
            shelf,
          ],
        );
      },
    );
  }

  /// The two-pane shelf's own scroller height: the panel's height less its
  /// chrome, so the rows scroll inside it instead of pushing the panel past the
  /// screen. Null (the whole body scrolls as one) when the room is too short -
  /// a keyboard, a gesture bar - or the text is large enough that the entries
  /// column outgrows the panel: a scroller half hidden by the outer scroll is
  /// worse than one scroll.
  double? _shelfHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (MediaQuery.textScalerOf(context).scale(100) > 115) return null;
    final bottom = math.max(mq.viewInsets.bottom, mq.viewPadding.bottom);
    final room = mq.size.height - mq.viewPadding.top - bottom - 32 - 50 - 44;
    return room < 120 ? null : math.min(room, 242);
  }
}

// ---- entries ---------------------------------------------------------------

class _Entries extends StatelessWidget {
  const _Entries({
    required this.photos,
    required this.tiles,
    required this.compact,
    required this.busyDoor,
    required this.onPhotos,
    required this.onFiles,
  });

  final bool photos;
  final bool tiles;
  final bool compact;
  final _Door busyDoor;
  final VoidCallback onPhotos;
  final VoidCallback onFiles;

  @override
  Widget build(BuildContext context) {
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final cloud = ios ? 'iCloud' : 'Drive';
    final (photoCopy, fileCopy) = photos
        ? (
            tiles
                ? 'Your camera roll'
                : compact
                ? 'Camera roll'
                : 'Your camera roll, no permission needed',
            tiles || compact
                ? 'Files, $cloud, downloads'
                : 'Files, ${ios ? 'iCloud Drive' : 'Google Drive'}, downloads',
          )
        : ('', 'Browse this computer for an MP4, MKV, MOV or WebM');
    final photoEntry = photos
        ? _SourceEntry(
            key: const ValueKey('entry-photos'),
            icon: BoothIcons.image,
            title: 'From Photos',
            subtitle: photoCopy,
            tile: tiles,
            compact: compact,
            busy: busyDoor == _Door.photos,
            onTap: busyDoor == _Door.none ? onPhotos : null,
          )
        : null;
    final filesEntry = _SourceEntry(
      key: const ValueKey('entry-files'),
      icon: BoothIcons.folder,
      title: 'From Files',
      subtitle: fileCopy,
      tile: tiles,
      compact: compact,
      busy: busyDoor == _Door.files,
      onTap: busyDoor == _Door.none ? onFiles : null,
    );
    if (tiles) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
            Expanded(child: photoEntry!),
            Expanded(child: filesEntry),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [?photoEntry, filesEntry],
    );
  }
}

class _SourceEntry extends StatefulWidget {
  const _SourceEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tile,
    required this.compact,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// The tablet form: icon over text, two across.
  final bool tile;
  final bool compact;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<_SourceEntry> createState() => _SourceEntryState();
}

class _SourceEntryState extends State<_SourceEntry> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final glyph = Container(
      width: w.tile ? 32 : 36,
      height: w.tile ? 32 : 36,
      decoration: BoxDecoration(
        color: PTColors.well,
        borderRadius: BorderRadius.circular(PTRadius.control),
        border: Border.all(color: PTColors.aisle),
      ),
      child: Icon(w.icon, size: 18, color: PTColors.primary),
    );
    final text = Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      spacing: w.tile ? 2 : 3,
      children: [
        Text(
          w.title,
          maxLines: 1,
          overflow: .ellipsis,
          // Half-rate past 1.0x, like every dialog heading: at a full 2x the
          // primary label would have to wrap or fold on a 320 pt phone.
          textScaler: dialogHeadingScaler(context),
          style: PTText.body.copyWith(fontSize: 15, fontWeight: .w600, color: PTColors.fg),
        ),
        Text(
          w.subtitle,
          maxLines: 3,
          overflow: .ellipsis,
          style: PTText.caption.copyWith(fontSize: 12, color: PTColors.fgMute),
        ),
      ],
    );
    final minHeight = w.tile
        ? 96.0
        : w.compact
        ? 56.0
        : 66.0;
    return Semantics(
      button: true,
      enabled: w.onTap != null,
      label: '${w.title}. ${w.subtitle}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: w.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: PTPressable(
          onTap: w.onTap,
          pressedScale: 0.99,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            curve: PTMotion.enter,
            constraints: BoxConstraints(minHeight: minHeight),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: w.tile ? 12 : 8),
            decoration: BoxDecoration(
              color: _hovered && w.onTap != null ? PTColors.aisle : Colors.transparent,
              borderRadius: BorderRadius.circular(PTRadius.control),
              border: Border.all(color: PTColors.aisle),
            ),
            child: w.tile
                ? Column(
                    crossAxisAlignment: .start,
                    mainAxisAlignment: .center,
                    spacing: 8,
                    children: [
                      Row(
                        mainAxisAlignment: .spaceBetween,
                        children: [glyph, if (w.busy) const PTLoader(size: 18)],
                      ),
                      text,
                    ],
                  )
                : Row(
                    spacing: 14,
                    children: [
                      glyph,
                      Expanded(child: text),
                      if (w.busy)
                        const PTLoader(size: 18)
                      else
                        const Icon(BoothIcons.chevronRight, size: 18, color: PTColors.fgMute),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ---- notice ----------------------------------------------------------------

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(
          color: PTColors.dangerSurface,
          borderRadius: BorderRadius.circular(PTRadius.control),
          border: Border.all(color: PTColors.dangerBorder.withValues(alpha: 0.4)),
        ),
        child: Row(
          spacing: 10,
          children: [
            const Icon(BoothIcons.alert, size: 18, color: PTColors.danger),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  message,
                  style: PTText.body.copyWith(fontSize: 13.5, height: 1.35, color: PTColors.fg),
                ),
              ),
            ),
            PTIconButton(
              icon: BoothIcons.close,
              glass: false,
              size: 44,
              iconSize: 16,
              tooltip: 'Dismiss',
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

// ---- the Recent shelf --------------------------------------------------------

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.entries,
    required this.unavailable,
    required this.busyId,
    required this.downloading,
    required this.compact,
    required this.now,
    required this.recents,
    required this.listHeight,
    required this.onOpen,
    required this.onRemove,
    required this.onLocate,
    required this.onClear,
  });

  final List<RecentVideo>? entries;
  final Map<String, UnavailableReason> unavailable;
  final String? busyId;
  final String? downloading;
  final bool compact;
  final DateTime now;
  final RecentVideos recents;

  /// Two-pane only: the rows scroll inside this height.
  final double? listHeight;
  final ValueChanged<RecentVideo> onOpen;
  final ValueChanged<RecentVideo> onRemove;
  final ValueChanged<RecentVideo> onLocate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final list = entries;
    // Not read yet: say nothing rather than flash "Nothing here yet".
    if (list == null) return const SizedBox.shrink();
    final rows = <Widget>[
      for (final e in list)
        _RecentRow(
          key: ValueKey(e.id),
          entry: e,
          recents: recents,
          now: now,
          compact: compact,
          reason: unavailable[e.id],
          busy: busyId == e.id,
          downloading: busyId == e.id && downloading != null,
          onOpen: () => onOpen(e),
          onRemove: () => onRemove(e),
          onLocate: () => onLocate(e),
        ),
    ];
    final body = list.isEmpty
        ? const _EmptyShelf()
        : listHeight != null
        ? SizedBox(
            height: listHeight,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) => rows[i],
            ),
          )
        : Column(spacing: 6, children: rows);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34),
          child: Row(
            mainAxisAlignment: .spaceBetween,
            children: [
              Text('RECENT', style: PTText.label.copyWith(fontSize: 11, color: PTColors.fgMute)),
              if (list.isNotEmpty) _TextAction(label: 'Clear all', onTap: onClear),
            ],
          ),
        ),
        body,
      ],
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: const DashedRectPainter(color: PTColors.rail, radius: PTRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 6,
          children: [
            const Icon(BoothIcons.clock, size: 22, color: PTColors.fgMute),
            Text(
              'Nothing here yet',
              textAlign: .center,
              style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600, color: PTColors.fg),
            ),
            Text(
              'Videos you open show up here, so next time it is one tap.',
              textAlign: .center,
              style: PTText.caption.copyWith(fontSize: 12.5, color: PTColors.fgMute),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap, this.icon, this.color});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? PTColors.fgDim;
    return Semantics(
      button: true,
      child: PTPressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget, minWidth: kMinTouchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: .min,
              mainAxisAlignment: .center,
              spacing: 8,
              children: [
                if (icon != null) Icon(icon, size: 16, color: ink),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: PTText.body.copyWith(
                      fontSize: 13.5,
                      fontWeight: color == null ? .w500 : .w600,
                      color: ink,
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

class _RecentRow extends StatefulWidget {
  const _RecentRow({
    super.key,
    required this.entry,
    required this.recents,
    required this.now,
    required this.compact,
    required this.reason,
    required this.busy,
    required this.downloading,
    required this.onOpen,
    required this.onRemove,
    required this.onLocate,
  });

  final RecentVideo entry;
  final RecentVideos recents;
  final DateTime now;
  final bool compact;

  /// Non-null once opening this row failed (or its file is plainly gone).
  final UnavailableReason? reason;
  final bool busy;
  final bool downloading;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final VoidCallback onLocate;

  @override
  State<_RecentRow> createState() => _RecentRowState();
}

class _RecentRowState extends State<_RecentRow> {
  late final Future<File?> _thumb = widget.recents.thumbnailFile(widget.entry.id);

  static String _why(UnavailableReason r, bool compact) => switch (r) {
    UnavailableReason.missing => compact ? 'File moved' : 'File moved or unavailable',
    UnavailableReason.permissionLost => 'Needs access again',
    UnavailableReason.unreadable => "Won't open right now",
    UnavailableReason.downloadTimedOut => 'Still downloading from iCloud',
  };

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final e = w.entry;
    final bad = w.reason != null;
    final thumbW = w.compact ? 56.0 : 64.0;
    final thumbH = w.compact ? 36.0 : 40.0;
    final meta = [
      if (e.duration != null) formatRuntime(e.duration!),
      if (e.sizeBytes != null) formatSize(e.sizeBytes!),
      'Opened ${formatOpened(e.lastOpened, w.now)}',
    ].join(' · ');
    final second = w.downloading
        ? 'Downloading from iCloud…'
        : w.busy
        ? 'Opening…'
        : bad
        ? _why(w.reason!, w.compact)
        : meta;
    final open = Semantics(
      button: true,
      label: '${e.displayName}. $second',
      excludeSemantics: true,
      child: PTPressable(
        onTap: w.busy ? null : w.onOpen,
        pressedScale: 0.99,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: w.compact ? 56 : 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
            child: Row(
              spacing: 12,
              children: [
                _Thumb(
                  future: _thumb,
                  width: thumbW,
                  height: thumbH,
                  duration: e.duration,
                  missing: bad,
                  working: w.busy,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    mainAxisSize: .min,
                    spacing: 3,
                    children: [
                      Text(
                        e.displayName,
                        maxLines: 2,
                        overflow: .ellipsis,
                        style: PTText.body.copyWith(
                          fontSize: 14,
                          fontWeight: .w600,
                          color: bad ? PTColors.white(0.6) : PTColors.fg,
                        ),
                      ),
                      Text(
                        second,
                        maxLines: 2,
                        overflow: .ellipsis,
                        style: PTText.caption.copyWith(
                          fontSize: 12,
                          color: bad ? PTColors.danger : PTColors.fgMute,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final remove = PTIconButton(
      icon: BoothIcons.close,
      glass: false,
      size: 44,
      iconSize: 16,
      tooltip: 'Remove from Recent',
      onPressed: w.onRemove,
    );
    return Container(
      decoration: BoxDecoration(
        color: bad ? PTColors.dangerSurface : null,
        borderRadius: BorderRadius.circular(PTRadius.control),
        border: Border.all(
          color: bad ? PTColors.dangerBorder.withValues(alpha: 0.33) : PTColors.aisle,
        ),
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              Expanded(child: open),
              if (bad && w.compact)
                _TextAction(
                  label: 'Locate',
                  icon: BoothIcons.search,
                  color: PTColors.primary,
                  onTap: w.onLocate,
                ),
              Padding(padding: const EdgeInsets.only(right: 6), child: remove),
            ],
          ),
          if (bad && !w.compact)
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: PTColors.aisle)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TextAction(
                      label: 'Locate file',
                      icon: BoothIcons.search,
                      color: PTColors.primary,
                      onTap: w.onLocate,
                    ),
                  ),
                  Container(width: 1, height: 44, color: PTColors.aisle),
                  Expanded(
                    child: _TextAction(label: 'Remove', onTap: w.onRemove),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The still saved the last time this file played, or - until one exists - the
/// board's placeholder: an Aisle tile with a play glyph. A missing file draws the
/// dashed stub with the alert glyph; a row being opened shows the loader.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.future,
    required this.width,
    required this.height,
    required this.duration,
    required this.missing,
    required this.working,
  });

  final Future<File?> future;
  final double width;
  final double height;
  final Duration? duration;
  final bool missing;
  final bool working;

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(
      child: working
          ? const PTLoader(size: 16)
          : Icon(
              missing ? BoothIcons.alert : BoothIcons.play,
              size: 18,
              color: missing ? PTColors.danger : PTColors.fgMute,
            ),
    );
    if (missing) {
      return SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          foregroundPainter: const DashedRectPainter(
            color: PTColors.rail,
            radius: PTRadius.control,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: PTColors.well,
              borderRadius: BorderRadius.circular(PTRadius.control),
            ),
            child: placeholder,
          ),
        ),
      );
    }
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PTColors.aisle,
        borderRadius: BorderRadius.circular(PTRadius.control),
        border: Border.all(color: PTColors.rail),
      ),
      child: Stack(
        fit: .expand,
        children: [
          FutureBuilder<File?>(
            future: future,
            builder: (context, snap) {
              final file = snap.data;
              if (file == null || working) return placeholder;
              return Image.file(
                file,
                fit: .cover,
                cacheWidth: 192,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder,
              );
            },
          ),
          if (duration != null && !working)
            Positioned(
              right: 3,
              bottom: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: PTColors.canvas,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  formatTimecode(duration!),
                  textScaler: .noScaling,
                  style: PTText.mono.copyWith(fontSize: 9, height: 1.2, color: PTColors.fg),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
