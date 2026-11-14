import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/player/local_video.dart';
import 'package:synctogether/rooms/local_media_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalMediaStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = LocalMediaStore(prefs: prefs);
  });

  group('LocalMediaStore', () {
    test('records and looks up local media entry', () async {
      await store.record(roomId: 'room-1', name: 'video.mp4', path: '/path/to/video.mp4');
      final entry = await store.lookup('room-1');
      expect(entry, isNotNull);
      expect(entry!.name, 'video.mp4');
      expect(entry.path, '/path/to/video.mp4');
    });

    test('remembers a content:// pick that has no path, through its reference', () async {
      await store.record(
        roomId: 'room-1',
        name: 'Movie.mkv',
        path: null,
        reference: const ContentUriReference('content://x/document/video%3A1'),
      );
      final entry = (await store.lookup('room-1'))!;
      expect(entry.name, 'Movie.mkv');
      expect(entry.path, 'content://x/document/video%3A1');
      expect(entry.fileStillExists, isTrue);
      // survives a restart (fresh store over the same prefs)
      final again = (await LocalMediaStore(prefs: await SharedPreferences.getInstance())
          .lookup('room-1'))!;
      expect(again.reference, isA<ContentUriReference>());
    });

    test('entries written before references existed still load', () async {
      SharedPreferences.setMockInitialValues({
        'pt.local_media_by_room': '{"r":{"name":"a.mp4","path":"/a.mp4","touched_at":1}}',
      });
      final old = LocalMediaStore(prefs: await SharedPreferences.getInstance());
      final entry = (await old.lookup('r'))!;
      expect(entry.reference, isNull);
      expect(entry.path, '/a.mp4');
    });

    test('a record with neither path nor reference is ignored', () async {
      await store.record(roomId: 'room-1', name: 'x', path: null);
      expect(await store.lookup('room-1'), isNull);
    });

    test('stores and clears upload sessions with clearAllUploadSessions', () async {
      const session = UploadSession(
        roomId: 'room-1',
        uploadId: 'up-123',
        r2Key: 'rooms/room-1/video.mp4',
        filePath: '/path/to/video.mp4',
        fileSize: 1000,
        partSizeBytes: 500,
        totalParts: 2,
      );

      await store.saveUploadSession(roomId: 'room-1', session: session);
      expect(await store.loadUploadSession('room-1'), isNotNull);

      await store.clearAllUploadSessions();
      expect(await store.loadUploadSession('room-1'), isNull);
    });

    test('clearAll wipes both local media entries and upload sessions', () async {
      await store.record(roomId: 'room-1', name: 'video.mp4', path: '/path/to/video.mp4');
      const session = UploadSession(
        roomId: 'room-1',
        uploadId: 'up-123',
        r2Key: 'rooms/room-1/video.mp4',
        filePath: '/path/to/video.mp4',
        fileSize: 1000,
        partSizeBytes: 500,
        totalParts: 2,
      );
      await store.saveUploadSession(roomId: 'room-1', session: session);

      expect(await store.lookup('room-1'), isNotNull);
      expect(await store.loadUploadSession('room-1'), isNotNull);

      await store.clearAll();

      expect(await store.lookup('room-1'), isNull);
      expect(await store.loadUploadSession('room-1'), isNull);
    });
  });
}
