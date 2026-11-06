import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/stream/stream_proxy.dart';
import 'package:synctogether/player/stream/stream_tuning.dart';
import 'package:synctogether/rooms/media_sharing_service.dart';

const _mib = 1024 * 1024;

void main() {
  group('remoteStreamOptions', () {
    test('desktop gets the deep cache, reconnects and a short wait for buffer', () {
      final o = remoteStreamOptions(device: .desktop, bitrateBps: 8000000);
      expect(o['demuxer-max-bytes'], '${256 * _mib}');
      expect(o['demuxer-readahead-secs'], '60');
      expect(o['cache'], 'yes');
      expect(o['cache-pause-initial'], 'yes');
      expect(o['cache-pause-wait'], '5');
      expect(o['stream-lavf-o'], contains('reconnect=1'));
      expect(o['stream-lavf-o'], contains('reconnect_streamed=1'));
      expect(o['stream-lavf-o'], contains('reconnect_delay_max=5'));
      expect(int.parse(o['network-timeout']!), greaterThan(5));
    });

    test('phones and tablets are bounded harder than desktop', () {
      int bytes(StreamDeviceClass d) =>
          int.parse(remoteStreamOptions(device: d)['demuxer-max-bytes']!);
      expect(bytes(.phone), inInclusiveRange(64 * _mib, 96 * _mib));
      expect(bytes(.tablet), lessThan(bytes(.desktop)));
      expect(bytes(.phone), lessThan(bytes(.tablet)));
    });

    test('read-ahead never asks for more seconds than the cache can hold', () {
      // 40 Mbps on a phone: 80 MiB holds about 13 s, so 60 s would thrash.
      final o = remoteStreamOptions(device: .phone, bitrateBps: 40000000);
      final secs = int.parse(o['demuxer-readahead-secs']!);
      expect(secs, lessThan(20));
      expect(secs, greaterThanOrEqualTo(10));
      // A low bitrate keeps the full window.
      expect(
        remoteStreamOptions(device: .desktop, bitrateBps: 2000000)['demuxer-readahead-secs'],
        '60',
      );
    });

    test('buffer ahead waits longer and reads deeper; escalation is the quiet version', () {
      final base = remoteStreamOptions(device: .desktop);
      final ahead = remoteStreamOptions(device: .desktop, bufferAhead: true);
      final quiet = remoteStreamOptions(device: .desktop, escalated: true);
      expect(int.parse(ahead['cache-pause-wait']!), kBufferAheadTargetSecs);
      expect(
        int.parse(ahead['demuxer-readahead-secs']!),
        greaterThan(int.parse(base['demuxer-readahead-secs']!)),
      );
      expect(
        int.parse(quiet['cache-pause-wait']!),
        greaterThan(int.parse(base['cache-pause-wait']!)),
      );
      expect(int.parse(quiet['cache-pause-wait']!), lessThan(kBufferAheadTargetSecs));
    });

    test('local files get media_kit defaults back, and demuxer-lavf-o is left alone', () {
      expect(localFileStreamOptions['cache-pause-initial'], 'no');
      expect(localFileStreamOptions['demuxer-readahead-secs'], '1');
      expect(localFileStreamOptions['demuxer-max-bytes'], '${32 * _mib}');
      expect(localFileStreamOptions['stream-lavf-o'], '');
      expect(localFileStreamOptions.containsKey('demuxer-lavf-o'), isFalse);
      expect(
        remoteStreamOptions(
          device: .desktop,
        ).keys.toSet().containsAll(localFileStreamOptions.keys.toSet()),
        isTrue,
        reason: 'every remote option must have a reset',
      );
    });
  });

  group('requiredBitrateBps', () {
    test('is size * 8 / duration, or null when unknown', () {
      expect(
        requiredBitrateBps(fileBytes: 1000000000, duration: const Duration(seconds: 200)),
        40000000,
      );
      expect(requiredBitrateBps(fileBytes: null, duration: const Duration(seconds: 200)), isNull);
      expect(requiredBitrateBps(fileBytes: 10, duration: null), isNull);
      expect(requiredBitrateBps(fileBytes: 0, duration: const Duration(seconds: 5)), isNull);
      expect(requiredBitrateBps(fileBytes: 10, duration: Duration.zero), isNull);
    });
  });

  group('server hints', () {
    test('missing or invalid hints keep today\'s defaults', () {
      for (final c in [
        streamConfigFromHints(),
        streamConfigFromHints(chunkBytes: 0, maxParallel: -3),
      ]) {
        expect(c.chunkSize, 8 * _mib);
        expect(c.maxParallelism, 4);
        expect(c.initialParallelism, 4);
      }
    });

    test('out-of-range hints are clamped to 4-32 MiB and 1-8 connections', () {
      expect(streamConfigFromHints(chunkBytes: 1024).chunkSize, 4 * _mib);
      expect(streamConfigFromHints(chunkBytes: 999 * _mib).chunkSize, 32 * _mib);
      expect(streamConfigFromHints(chunkBytes: 16 * _mib).chunkSize, 16 * _mib);
      expect(streamConfigFromHints(maxParallel: 100).maxParallelism, 8);
      final one = streamConfigFromHints(maxParallel: 1);
      expect(one.maxParallelism, 1);
      expect(one.initialParallelism, 1);
      expect(one.minParallelism, 1);
      final six = streamConfigFromHints(maxParallel: 6);
      expect(six.initialParallelism, 4);
      expect(six.maxParallelism, 6);
    });

    test('the download-url fields are parsed defensively', () {
      expect(DownloadUrlResult.parseChunkBytes(null), isNull);
      expect(DownloadUrlResult.parseChunkBytes('8'), isNull);
      expect(DownloadUrlResult.parseChunkBytes(double.nan), isNull);
      expect(DownloadUrlResult.parseChunkBytes(-5), isNull);
      expect(DownloadUrlResult.parseChunkBytes(8 * _mib), 8 * _mib);
      expect(DownloadUrlResult.parseChunkBytes(1), 4 * _mib);
      expect(DownloadUrlResult.parseChunkBytes(1e12), 32 * _mib);
      expect(DownloadUrlResult.parseMaxParallel(null), isNull);
      expect(DownloadUrlResult.parseMaxParallel(0), isNull);
      expect(DownloadUrlResult.parseMaxParallel(3), 3);
      expect(DownloadUrlResult.parseMaxParallel(50), 8);
      expect(DownloadUrlResult.parseMaxParallel(2.9), 2);
    });
  });
}
