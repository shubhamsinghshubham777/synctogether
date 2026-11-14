import 'dart:async';
import 'dart:io';

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/player/local_video_chooser.dart';
import 'package:synctogether/player/media_access.dart';
import 'package:synctogether/player/media_file_types.dart';
import 'package:synctogether/player/photo_picker.dart';
import 'package:synctogether/player/recent_videos.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_theme.dart';

import 'fake_media_access.dart';

// The chooser's behaviour against fake pickers, a fake native seam and a real
// RecentVideos over mock preferences. Layout is test/layout/dialogs_matrix_test.

void main() {
  late Directory media;
  late FakeMediaAccess fake;
  late RecentVideos recents;
  late LocalVideoAccess access;
  var now = DateTime(2026, 11, 6, 12);

  // Outside any tmp/ or cache/ segment, which Recent would refuse to remember.
  File mediaFile(String name) => File('${media.path}/$name')..createSync(recursive: true);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    media = Directory('build/chooser_test_media')..createSync(recursive: true);
    fake = FakeMediaAccess();
    now = DateTime(2026, 11, 6, 12);
    access = LocalVideoAccess(platform: fake, isIOS: false, isDesktop: true);
    recents = RecentVideos(
      prefs: prefs,
      access: access,
      thumbnailDir: () async => Directory('${media.path}/thumbs'),
      clock: () => now,
    );
  });

  tearDown(() {
    if (media.existsSync()) media.deleteSync(recursive: true);
  });

  LocalVideo videoAt(String path, {String? name, VideoReference? ref}) => LocalVideo(
    name: name ?? path.split('/').last,
    mediaUri: path,
    path: path,
    origin: VideoOrigin.files,
    reference: ref ?? PathReference(path),
    sizeBytes: 1000,
  );

  LocalVideoChooserServices services({
    FilePick? pickFile,
    PickPhotoVideo? pickPhoto,
    bool photos = true,
    LocalVideoAccess? withAccess,
  }) => LocalVideoChooserServices(
    access: withAccess ?? access,
    recents: recents,
    pickFile: pickFile ?? () async => null,
    pickPhoto: pickPhoto ?? () async => null,
    showPhotos: photos,
    probeMissing: true,
    clock: () => now,
  );

  /// Opens the chooser and returns what it eventually resolves to.
  Future<Future<LocalVideoChoice?>> open(WidgetTester tester, LocalVideoChooserServices svc) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPTTheme(),
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    final result = showLocalVideoChooser(ctx, services: svc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return result;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('From Files adopts the pick, hands it back, and the caller records it', (
    tester,
  ) async {
    final file = mediaFile('Movie Night.mkv');
    final svc = services(
      pickFile: () async => FastFilePickerPath.fromPath('Movie Night.mkv', file.absolute.path),
    );
    final result = await open(tester, svc);
    await tester.tap(find.text('From Files'));
    await settle(tester);

    final choice = (await result)!;
    expect(choice.source, ChoiceSource.files);
    expect(choice.video.name, 'Movie Night.mkv');
    expect(find.text('Choose a video'), findsNothing, reason: 'the chooser closed');

    // The chooser never records: the caller does, once the player has opened it.
    expect(await recents.list(), isEmpty);
    final entry = await recents.record(choice.video);
    expect(entry, isNotNull);
    expect((await recents.list()).single.displayName, 'Movie Night.mkv');
  });

  testWidgets('a Photos pick comes back as photos and is not remembered', (tester) async {
    final file = mediaFile('IMG_0042.MOV');
    final svc = services(
      pickPhoto: () async => PhotoPick(path: file.absolute.path, name: 'IMG_0042.MOV'),
    );
    final result = await open(tester, svc);
    await tester.tap(find.text('From Photos'));
    await settle(tester);

    final choice = (await result)!;
    expect(choice.source, ChoiceSource.photos);
    expect(choice.video.origin, VideoOrigin.photos);
    expect(await recents.record(choice.video), isNull, reason: 'a Photos export is not durable');
    expect(await recents.list(), isEmpty);
  });

  testWidgets('desktop shows Files and Recent only', (tester) async {
    await open(tester, services(photos: false));
    expect(find.text('From Photos'), findsNothing);
    expect(find.text('From Files'), findsOneWidget);
    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('a non-video pick keeps the chooser open with the friendly banner', (tester) async {
    final svc = services(
      pickFile: () async => FastFilePickerPath.fromPath('notes.pdf', '/docs/notes.pdf'),
    );
    final result = await open(tester, svc);
    var done = false;
    unawaited(result.then((_) => done = true));
    await tester.tap(find.text('From Files'));
    await settle(tester);

    expect(find.text(kNotAVideoMessage), findsOneWidget);
    expect(find.text('Choose a video'), findsOneWidget, reason: 'still open');
    expect(done, isFalse);
    expect(fake.log, isEmpty, reason: 'nothing was adopted, so nothing holds access');

    // The banner dismisses; the entries still work after it.
    await tester.tap(find.byTooltip('Dismiss'));
    await settle(tester);
    expect(find.text(kNotAVideoMessage), findsNothing);
    expect(find.text('From Files'), findsOneWidget);
  });

  testWidgets('a cancelled picker changes nothing', (tester) async {
    final result = await open(tester, services());
    var done = false;
    unawaited(result.then((_) => done = true));
    await tester.tap(find.text('From Files'));
    await settle(tester);
    expect(find.text('Choose a video'), findsOneWidget);
    expect(find.text(kNotAVideoMessage), findsNothing);
    expect(done, isFalse);
  });

  testWidgets('a moved file shows Locate and Remove; Locate swaps in the new file', (tester) async {
    final gone = '${media.absolute.path}/gone/Old Cut.mkv';
    await recents.record(videoAt(gone));
    final found = mediaFile('Old Cut (found).mkv');
    final svc = services(
      pickFile: () async => FastFilePickerPath.fromPath('Old Cut (found).mkv', found.absolute.path),
    );
    final result = await open(tester, svc);

    expect(find.text('File moved or unavailable'), findsOneWidget);
    expect(find.text('Locate file'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Locate file'));
    await settle(tester);

    final choice = (await result)!;
    expect(choice.video.name, 'Old Cut (found).mkv');
    expect(choice.source, ChoiceSource.files);
    expect(
      (await recents.list()).where((e) => e.displayName == 'Old Cut.mkv'),
      isEmpty,
      reason: 'the stale entry is replaced, not left beside the new one',
    );
  });

  testWidgets('Remove on a moved row forgets just that row', (tester) async {
    final ok = mediaFile('Fine.mp4');
    await recents.record(videoAt(ok.absolute.path));
    await recents.record(videoAt('${media.absolute.path}/gone/Lost.mp4'));
    await open(tester, services());
    expect(find.text('Lost.mp4'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await settle(tester);

    expect(find.text('Lost.mp4'), findsNothing);
    expect(find.text('Fine.mp4'), findsOneWidget);
    expect((await recents.list()).map((e) => e.displayName), ['Fine.mp4']);
  });

  testWidgets('Clear all empties the shelf and shows the empty state', (tester) async {
    for (final n in ['One.mp4', 'Two.mkv']) {
      await recents.record(videoAt(mediaFile(n).absolute.path));
    }
    await open(tester, services());
    expect(find.text('One.mp4'), findsOneWidget);
    expect(find.text('Two.mkv'), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await settle(tester);

    expect(find.text('One.mp4'), findsNothing);
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Clear all'), findsNothing);
    expect(await recents.list(), isEmpty);
  });

  testWidgets('tapping a recent row reopens it and refreshes its place on the shelf', (
    tester,
  ) async {
    final a = mediaFile('Older.mp4');
    final b = mediaFile('Newer.mp4');
    now = DateTime(2026, 11, 5);
    await recents.record(videoAt(a.absolute.path), duration: const Duration(minutes: 95));
    now = DateTime(2026, 11, 6, 9);
    await recents.record(videoAt(b.absolute.path));
    now = DateTime(2026, 11, 6, 12);

    final result = await open(tester, services());
    expect(find.textContaining('1h 35m'), findsOneWidget, reason: 'runtime shown');
    await tester.tap(find.text('Older.mp4'));
    await settle(tester);

    final choice = (await result)!;
    expect(choice.source, ChoiceSource.recent);
    expect(choice.video.name, 'Older.mp4');
    expect((await recents.list()).first.displayName, 'Older.mp4', reason: 'jumped to the top');
  });

  testWidgets('an unreadable recent row says so in the row, not a banner', (tester) async {
    // A content:// reference the provider can no longer stat.
    await recents.record(
      LocalVideo(
        name: 'Shared.mp4',
        mediaUri: 'content://p/1',
        contentUri: 'content://p/1',
        origin: VideoOrigin.files,
        reference: const ContentUriReference('content://p/1'),
        sizeBytes: 5,
      ),
    );
    fake.stat = null;
    await open(tester, services());
    await tester.tap(find.text('Shared.mp4'));
    await settle(tester);

    expect(find.text('Needs access again'), findsOneWidget);
    expect(find.text('Locate file'), findsOneWidget);
    expect(find.text('Choose a video'), findsOneWidget, reason: 'still open');
  });

  testWidgets('an iCloud file shows PTLoader and the downloading copy, then opens', (tester) async {
    final gate = Completer<void>();
    final ios = LocalVideoAccess(
      platform: fake,
      isIOS: true,
      isDesktop: false,
      delay: (_) => gate.future,
    );
    final entryPath = '${media.absolute.path}/cloud/Big.mkv';
    final ref = BookmarkReference(bookmark: 'BM', lastKnownPath: entryPath);
    await recents.record(videoAt(entryPath, ref: ref));
    fake.resolved = ResolvedBookmark(url: 'file://$entryPath', path: entryPath);
    fake.availability.addAll([
      LocalAvailability.downloading,
      LocalAvailability.downloading,
      LocalAvailability.local,
    ]);

    final svc = LocalVideoChooserServices(
      access: ios,
      recents: recents,
      pickFile: () async => null,
      pickPhoto: () async => null,
      showPhotos: true,
      probeMissing: false,
      clock: () => now,
    );
    final result = await open(tester, svc);
    await tester.tap(find.text('Big.mkv'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Downloading from iCloud…'), findsOneWidget);
    expect(find.byType(PTLoader), findsWidgets);

    gate.complete();
    await settle(tester);
    final choice = (await result)!;
    expect(choice.video.name, 'Big.mkv');
    expect(choice.source, ChoiceSource.recent);
  });

  testWidgets('an iCloud download that gives up releases access and says so', (tester) async {
    final ios = LocalVideoAccess(
      platform: fake,
      isIOS: true,
      isDesktop: false,
      delay: (_) async {},
    );
    final p = '${media.absolute.path}/cloud/Never.mkv';
    await recents.record(
      videoAt(
        p,
        ref: BookmarkReference(bookmark: 'BM', lastKnownPath: p),
      ),
    );
    fake.resolved = ResolvedBookmark(url: 'file://$p', path: p);
    fake.defaultAvailability = LocalAvailability.downloading;
    final svc = LocalVideoChooserServices(
      access: ios,
      recents: recents,
      pickFile: () async => null,
      pickPhoto: () async => null,
      showPhotos: true,
      probeMissing: false,
      clock: () => now,
    );
    await open(tester, svc);
    await tester.tap(find.text('Never.mkv'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Still downloading from iCloud'), findsOneWidget);
    expect(fake.log, contains('stop'), reason: 'the security scope was given back');
  });

  testWidgets('the sheet and the dialog are the same chooser', (tester) async {
    await open(tester, services());
    // 390 wide: a bottom sheet with stacked entries.
    expect(find.byKey(kGlassSheetKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('entry-photos'))).height,
      greaterThanOrEqualTo(44),
    );
  });
}
