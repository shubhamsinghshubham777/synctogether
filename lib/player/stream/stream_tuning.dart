/// How mpv is told to read a *remote* shared-media stream, as plain data.
///
/// Delivery only: nothing here touches the file's bytes. mpv's defaults suit a
/// local disk (one second of read-ahead, short timeouts, no pause-for-buffer),
/// which is exactly wrong for a presigned object store a continent away, so a
/// remote stream gets deeper read-ahead and a short wait for buffer before it
/// starts, and a local file gets the defaults back.
///
/// Pure on purpose: platform and bitrate in, option map out, so the numbers are
/// unit-tested and `RoomScreen` only has to apply the result.
library;

import 'dart:math' as math;

enum StreamDeviceClass { desktop, tablet, phone }

const int _mib = 1024 * 1024;

/// Seconds of media mpv's demuxer reads ahead of the playhead.
const int kStreamReadaheadSecs = 60;

/// How much runway [remoteStreamOptions] asks for before "buffer ahead" and
/// what a boosted stream gets, in seconds of media.
const int kBufferAheadTargetSecs = 30;

/// Demuxer cache ceiling per device class, in bytes. Phones are bounded hard:
/// mpv holds this in RAM, and iOS reaps a process that balloons.
int streamCacheBytes(StreamDeviceClass device) => switch (device) {
  StreamDeviceClass.desktop => 256 * _mib,
  StreamDeviceClass.tablet => 128 * _mib,
  StreamDeviceClass.phone => 80 * _mib,
};

int _backBytes(StreamDeviceClass device) => switch (device) {
  StreamDeviceClass.desktop => 64 * _mib,
  StreamDeviceClass.tablet => 32 * _mib,
  StreamDeviceClass.phone => 16 * _mib,
};

/// mpv properties for a remote shared-media stream.
///
/// [bitrateBps] is the file's average bitrate (size * 8 / duration) when
/// known. The read-ahead is capped so it never asks for more seconds than the
/// byte ceiling can hold at that bitrate - a 40 Mbps film on a phone cannot
/// buffer a minute in 80 MiB, and asking for it would just thrash the cache.
/// [bufferAhead] is the viewer's "let it buffer ahead" request: a longer wait
/// before resuming and a deeper read-ahead. [escalated] is the silent version
/// of the same help, applied when the probe says the shortfall is ours.
Map<String, String> remoteStreamOptions({
  required StreamDeviceClass device,
  int? bitrateBps,
  bool bufferAhead = false,
  bool escalated = false,
}) {
  final maxBytes = streamCacheBytes(device);
  final deep = bufferAhead || escalated;
  var readahead = deep ? 90 : kStreamReadaheadSecs;
  if (bitrateBps != null && bitrateBps > 0) {
    final holdable = (maxBytes * 8 / bitrateBps * 0.8).floor();
    readahead = math.min(readahead, math.max(10, holdable));
  }
  if (device == StreamDeviceClass.phone) readahead = math.min(readahead, deep ? 60 : 45);
  final pauseWait = bufferAhead
      ? kBufferAheadTargetSecs
      : escalated
      ? 10
      : (device == StreamDeviceClass.phone ? 6 : 5);
  if (bufferAhead) readahead = math.max(readahead, kBufferAheadTargetSecs + 15);
  return {
    'cache': 'yes',
    'demuxer-readahead-secs': '$readahead',
    'demuxer-max-bytes': '$maxBytes',
    'demuxer-max-back-bytes': '${_backBytes(device)}',
    'cache-pause': 'yes',
    'cache-pause-initial': 'yes',
    'cache-pause-wait': '$pauseWait',
    'network-timeout': '15',
    // Protocol-level reconnects belong on the stream, not the demuxer:
    // `demuxer-lavf-o` is already owned by media_kit (protocol whitelist,
    // segment retries) and setting it here would replace that list.
    'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',
  };
}

/// What a local file (or YouTube hand-off) gets back: media_kit's own values,
/// so a room that streams one film and then opens a local file is not left
/// with a 256 MiB cache and a pause-before-play it never asked for.
const Map<String, String> localFileStreamOptions = {
  'demuxer-readahead-secs': '1',
  'demuxer-max-bytes': '33554432',
  'demuxer-max-back-bytes': '33554432',
  'cache-pause': 'yes',
  'cache-pause-initial': 'no',
  'cache-pause-wait': '1',
  'network-timeout': '5',
  'stream-lavf-o': '',
};

/// Average bitrate in bits per second, or null when either input is unknown.
int? requiredBitrateBps({required int? fileBytes, required Duration? duration}) {
  if (fileBytes == null || fileBytes <= 0 || duration == null) return null;
  final secs = duration.inMilliseconds / 1000;
  if (secs < 1) return null;
  return (fileBytes * 8 / secs).round();
}

/// What mpv reports back for the two lavf option boxes after the tuning went in.
///
/// The reconnect settings live in `stream-lavf-o` on purpose (media_kit owns
/// `demuxer-lavf-o` for its protocol whitelist), so the only way to know the
/// bundled libmpv honours them is to read them back. `reconnectApplied` is
/// whether our options are present; `whitelistIntact` is whether media_kit's
/// whitelist in the demuxer box is still there (we must never have replaced it).
/// Either being false is a finding, not an error for the viewer.
({bool reconnectApplied, bool whitelistIntact}) verifyLavfOptions({
  required String? streamLavf,
  required String? demuxerLavf,
}) => (
  reconnectApplied: (streamLavf ?? '').contains('reconnect=1'),
  whitelistIntact: (demuxerLavf ?? '').contains('protocol_whitelist'),
);
