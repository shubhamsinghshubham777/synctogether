import 'dart:async';

import 'package:synctogether/rooms/room_models.dart';

/// How far a member has got towards having the room's canonical media loaded.
/// Declaration order is the rank - "more ready" compares by [index], which is
/// what resolves a multi-device user to a single status.
enum ReadyStatus {
  none,
  selecting,
  loading,
  ready;

  static ReadyStatus fromWire(String? value) => switch (value) {
    'selecting' => .selecting,
    'loading' => .loading,
    'ready' => .ready,
    _ => .none,
  };

  String get wire => name;
}

class PresentMember {
  const PresentMember({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    this.avatarUrl,
    this.readyStatus = .none,
    this.loadedFileName,
    this.loadedDuration,
    this.confirmedMedia,
    this.privacyMode = false,
  });

  final String userId;
  final String displayName;
  final String role;
  final DateTime joinedAt;
  final String? avatarUrl;

  /// A client that predates the readiness gate sends no status, which reads as
  /// [ReadyStatus.none] and holds the gate shut - the accepted trade-off.
  final ReadyStatus readyStatus;

  /// Basename this member actually has open, for the "they have `weird.mp4`" copy.
  final String? loadedFileName;

  /// Length of that file as this member's player reports it. Absent from older
  /// clients, which then fall back to the name alone.
  final Duration? loadedDuration;

  /// [gateMediaKey] of the canonical media this member told us "this is the
  /// same movie" about. Tied to one media row, so a new pick voids it.
  final String? confirmedMedia;

  final bool privacyMode;

  bool get isHost => role == 'host';
  bool get isReady => readyStatus == .ready;

  PresentMember withPrivacyMode(bool value) => PresentMember(
    userId: userId,
    displayName: displayName,
    role: role,
    joinedAt: joinedAt,
    avatarUrl: avatarUrl,
    readyStatus: readyStatus,
    loadedFileName: loadedFileName,
    loadedDuration: loadedDuration,
    confirmedMedia: confirmedMedia,
    privacyMode: value,
  );
}

/// Tri-state on purpose: before the first presence sync we simply don't know
/// who is in the room, and rendering that as `closed` flashes the waiting
/// overlay on every entry.
enum GateState { indeterminate, open, closed }

class ChatMessage {
  const ChatMessage({
    required this.senderId,
    required this.displayName,
    required this.content,
    required this.sentAt,
  });

  final String senderId;
  final String displayName;
  final String content;
  final DateTime sentAt;
}

enum RemoteActionKind { play, pause, seek }

/// A user-initiated remote playback action, surfaced for attribution UI. Only
/// emitted for genuine play/pause/seek broadcasts - never for mechanical
/// `state_response` application or `position_sync` drift correction, so
/// late-join and drift never read as someone touching the controls.
class RemoteAction {
  const RemoteAction({required this.senderId, required this.kind, this.position});

  final String senderId;
  final RemoteActionKind kind;
  final Duration? position;
}

/// History rows carry DB timestamps while live broadcasts carry sender-clock
/// timestamps, so exact keys don't exist - fuzzy-match to dedupe. Broadcasts
/// never replay, so this reload is the only way messages sent while we were
/// disconnected ever arrive.
const kChatMergeWindow = Duration(seconds: 10);

bool chatMessagesMatch(ChatMessage a, ChatMessage b) =>
    a.senderId == b.senderId &&
    a.content == b.content &&
    a.sentAt.difference(b.sentAt).abs() <= kChatMergeWindow;

void mergeChatHistory(List<ChatMessage> into, List<ChatMessage> history) {
  for (final h in history) {
    if (!into.any((m) => chatMessagesMatch(m, h))) into.add(h);
  }
  into.sort((a, b) => a.sentAt.compareTo(b.sentAt));
}

/// `messages.content` is `char_length(content) between 1 and 500`, and
/// Postgres counts *codepoints*. Flutter's `maxLength` counts graphemes, so the
/// two agree on text and disagree on emoji: 👩🏽‍💻 is one grapheme and four
/// codepoints. Counting runes here is what stops an emoji-heavy message passing
/// the field and bouncing off the insert.
const kChatMaxCodepoints = 500;

bool chatLengthOk(String text) => text.runes.length <= kChatMaxCodepoints;

/// How far two copies of a film may differ in length and still be one film.
///
/// +-1.5 s covers what containers legitimately disagree on for identical
/// content: mkv/webm report the segment duration from the last cluster, mp4
/// from the longest track (audio padding of an AAC priming frame is ~21-46 ms,
/// but a trailing silent or subtitle-only track can add a second), and avi is
/// derived from frame count / frame rate. A PAL speed-up (24 to 25 fps, ~4%) is
/// minutes on a feature, so it is far outside this and needs the name to agree.
const kGateDurationTolerance = Duration(milliseconds: 1500);

/// Why a member's file was accepted for the room's canonical media.
enum GateMatch { exactName, sameTitle, sameLength, confirmed }

const _kVideoExtensions = {
  'mkv', 'mp4', 'm4v', 'mov', 'avi', 'webm', 'wmv', 'flv', 'ts', 'm2ts', 'mts', //
  'mpg', 'mpeg', '3gp', 'ogv', 'vob', 'divx', 'asf', 'f4v', 'rmvb',
};

const _kQualityTags = {
  '360p', '480p', '540p', '576p', '720p', '1080p', '1440p', '2160p', '4k', '8k', //
  'uhd', 'hd', 'fhd', 'bluray', 'bdrip', 'brrip', 'bdremux', 'remux', 'webrip', //
  'webdl', 'hdrip', 'dvdrip', 'hdtv', 'x264', 'x265', 'h264', 'h265', 'hevc', //
  'avc', 'xvid', 'aac', 'ac3', 'eac3', 'dts', 'ddp5', 'atmos', 'flac', '10bit', //
  '8bit', 'hdr', 'hdr10', 'sdr', 'proper', 'repack', 'extended', 'unrated', //
  'remastered', 'yify', 'yts', 'rarbg', 'amzn', 'dsnp', 'hmax', //
};

final _kEpisodeMarker = RegExp(
  r'^(s\d{1,2}e\d{1,3}|\d{1,2}x\d{1,3}|e\d{1,3}|ep\d{1,3}|cd\d|part\d)$',
);

/// What survives of a file name once the things that vary between copies of
/// the same film are removed. [title] is what is compared; [year] only
/// vetoes a match when both sides state one and they differ (a remake); and
/// [markers] (episode / part numbers) are never stripped and veto the length
/// signal, because two episodes of one show routinely run the same length.
typedef MediaStem = ({String title, String? year, Set<String> markers});

MediaStem mediaStem(String fileName) {
  var name = fileName.trim().toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot > 0 && _kVideoExtensions.contains(name.substring(dot + 1))) {
    name = name.substring(0, dot);
  }
  // A re-download's "Movie (1)" suffix is the same file, not a different one.
  name = name.replaceFirst(RegExp(r'\s*\(\d{1,2}\)\s*$'), '');
  // Hyphenated or dotted compound tags must survive the separator split, as
  // must audio layouts like 5.1.
  name = name
      .replaceAll(RegExp(r'web[\s._-]?dl'), 'webdl')
      .replaceAll(RegExp(r'blu[\s._-]?ray'), 'bluray')
      .replaceAllMapped(RegExp(r'(?<!\d)([257])[.]([01])(?!\d)'), (m) => '${m[1]}x${m[2]}audio');
  final tokens = name.split(RegExp(r'[\s._\-\[\](){}+,;:]+')).where((t) => t.isNotEmpty).toList();
  String? year;
  final markers = <String>{};
  final title = <String>[];
  for (final t in tokens) {
    if (_kEpisodeMarker.hasMatch(t)) {
      markers.add(t);
      title.add(t);
    } else if (RegExp(r'^(19|20)\d{2}$').hasMatch(t) && tokens.length > 1) {
      year ??= t;
    } else if ((_kQualityTags.contains(t) || RegExp(r'^[257]x[01]audio$').hasMatch(t)) &&
        tokens.length > 1) {
      // quality / source / codec noise
    } else {
      title.add(t);
    }
  }
  // "1917" or "2012" are titles, not release years: a name that is nothing but
  // a year keeps it.
  if (title.isEmpty && year != null) return (title: year, year: null, markers: markers);
  return (title: title.join(' '), year: year, markers: markers);
}

/// Whether two file names plausibly name the same film.
bool sameMediaTitle(String a, String b) {
  final x = mediaStem(a);
  final y = mediaStem(b);
  if (x.title.isEmpty || x.title != y.title) return false;
  return x.year == null || y.year == null || x.year == y.year;
}

/// Key a member's "this is the same movie" confirmation is tied to.
String gateMediaKey(RoomMedia media) =>
    '${media.updatedAt?.millisecondsSinceEpoch ?? 0}:${media.name}';

/// Whether [loaded] is within [kGateDurationTolerance] of [canonical]. False
/// when either side is unknown - an absent length is never evidence.
bool durationsAgree(Duration? loaded, Duration? canonical) =>
    loaded != null &&
    canonical != null &&
    loaded > Duration.zero &&
    canonical > Duration.zero &&
    (loaded - canonical).abs() <= kGateDurationTolerance;

/// The rule that decides whether a member's local file counts as the room's
/// film, or null when it does not. Pure and shared by every client, so the room
/// agrees on who is holding the gate.
///
///  1. exact name (every client that ever existed)
///  2. same normalised title (case, extension, separators, year and quality
///     tags ignored) - a name the user chose, so it settles it
///  3. length within [kGateDurationTolerance] - for renamed or provider-mangled
///     copies, unless both names carry different episode/part markers
///  4. the member said so ([PresentMember.confirmedMedia])
///
/// Differing on all of these is "not ready"; the member is never trapped, as 4
/// is always one tap away.
GateMatch? gateMatchOf(PresentMember member, RoomMedia media) {
  final loaded = member.loadedFileName;
  final canonical = media.name;
  if (loaded != null && canonical != null) {
    if (loaded == canonical) return GateMatch.exactName;
    if (sameMediaTitle(loaded, canonical)) return GateMatch.sameTitle;
    if (durationsAgree(member.loadedDuration, media.duration)) {
      final a = mediaStem(loaded).markers;
      final b = mediaStem(canonical).markers;
      final conflict = a.isNotEmpty && b.isNotEmpty && !(a.length == b.length && a.containsAll(b));
      if (!conflict) return GateMatch.sameLength;
    }
  }
  if (member.confirmedMedia != null && member.confirmedMedia == gateMediaKey(media)) {
    return GateMatch.confirmed;
  }
  return null;
}

/// `ready` only means "something is open" - the match is the gate's job, which
/// is what lets the UI tell "still loading" apart from "loaded the wrong
/// thing".
bool memberSatisfiesGate(PresentMember member, RoomMedia media) {
  if (!member.isReady) return false;
  if (media.kind == .local) return gateMatchOf(member, media) != null;
  return true;
}

bool memberClearsGate(PresentMember member, RoomMedia media, Set<String> waived) =>
    memberSatisfiesGate(member, media) || waived.contains(member.userId);

/// Nobody may start or scrub until every present member has the room's
/// canonical media loaded.
GateState evaluateGateState({
  required bool hasPresenceSynced,
  required RoomMedia media,
  required List<PresentMember> members,
  Set<String> waived = const {},
  String mediaUploadState = 'none',
}) {
  if (!hasPresenceSynced) return .indeterminate;
  if (!media.isSet) return .closed;
  if (mediaUploadState == 'uploading') return .closed;
  if (members.isEmpty) return .indeterminate;
  return members.every((m) => memberClearsGate(m, media, waived)) ? .open : .closed;
}

/// Everyone the room is still waiting on, for overlay/banner copy.
List<PresentMember> gateBlockersOf(
  RoomMedia media,
  List<PresentMember> members, {
  Set<String> waived = const {},
}) => media.isSet ? members.where((m) => !memberClearsGate(m, media, waived)).toList() : const [];

/// Who the room is *actually being held up by* right now.
///
/// Narrower than [gateBlockersOf] on purpose, and the narrowing is the whole
/// point: at room entry, and for the seconds after any media change, *nobody*
/// has the file open yet, and calling all of them blockers would mean every
/// session was held up by everyone. That is what made the "never held the gate"
/// award - and the achievement built on it - unreachable.
///
/// Somebody is holding the gate only when at least one other present member has
/// already cleared it, i.e. there is somebody waiting on them.
Set<String> gateHolderIds(
  RoomMedia media,
  List<PresentMember> members, {
  Set<String> waived = const {},
}) {
  if (!media.isSet || members.length < 2) return const {};
  final blockers = gateBlockersOf(media, members, waived: waived);
  if (blockers.isEmpty || blockers.length == members.length) return const {};
  return {for (final m in blockers) m.userId};
}

/// What the gate derives from a state change. Only the authority acts on it,
/// else the room gets one pause per member.
enum GateTransition { pause, resume }

GateTransition? gateTransitionFor({
  required GateState previous,
  required GateState next,
  required bool isAuthority,
  required bool roomPlaying,
  required bool pausedByGate,
}) {
  if (!isAuthority) return null;
  if (next == GateState.closed && previous == GateState.open) {
    // The decision is room-level: when the host opens a new file their own
    // player stops while everyone else plays on, and that is exactly when the
    // gate must pause - so it cannot be made from our own `isPlaying`.
    return roomPlaying ? GateTransition.pause : null;
  }
  if (next == GateState.open && previous == GateState.closed && pausedByGate) {
    return GateTransition.resume;
  }
  return null;
}

/// Our own position is only meaningful if we still have the room's media
/// loaded. If we are the one holding the gate up we have just opened something
/// else and sit at 0 - resuming everyone there would throw the room back to the
/// start. A null held position simply skips the realignment seek.
Duration? gateHeldPosition({
  required String? subjectUserId,
  required String userId,
  required Duration? Function() position,
}) => subjectUserId == userId ? null : position();

bool shouldAutoReopenLocalFile({
  required RoomMedia media,
  required String? storedFileName,
  required bool storedFileExists,
  required String? loadedFileName,
  required bool isPickerOpen,
}) {
  if (media.kind != .local || media.name == null) return false;
  if (isPickerOpen) return false;
  if (loadedFileName == media.name) return false;
  if (storedFileName != media.name) return false;
  return storedFileExists;
}

/// Whether the quiet "streaming the shared copy" notice is owed: a member whose
/// device remembered this very file for the room, but can no longer open it, is
/// about to be handed the host's copy. Never for a host, and never when this
/// device had no copy to lose (that is just the normal first-time path).
bool shouldNoteStreamingFallback({
  required bool isHost,
  required String? mediaName,
  required String? storedFileName,
  required bool storedFileUsable,
}) => !isHost && mediaName != null && storedFileName == mediaName && !storedFileUsable;

Duration playablePosition(Duration reported) => reported < Duration.zero ? Duration.zero : reported;

const kResumeTailWindow = Duration(seconds: 15);

Duration? resumeSeekPosition({required Duration? held, required Duration? mediaDuration}) {
  if (held == null || held <= Duration.zero) return null;
  if (mediaDuration != null && mediaDuration > Duration.zero) {
    if (held >= mediaDuration - kResumeTailWindow) return null;
    return held;
  }
  return held;
}

/// Host if present, else the earliest joiner; user id breaks ties so every
/// client elects the same person.
String? authorityAmong(Iterable<PresentMember> candidates) {
  if (candidates.isEmpty) return null;
  final host = candidates.where((m) => m.isHost).firstOrNull;
  if (host != null) return host.userId;
  return candidates.reduce((a, b) {
    final cmp = a.joinedAt.compareTo(b.joinedAt);
    if (cmp != 0) return cmp < 0 ? a : b;
    return a.userId.compareTo(b.userId) < 0 ? a : b;
  }).userId;
}

/// Collapses a channel's presence payloads to one entry per user. A user with
/// two devices counts once; of their devices the most-ready wins, so a second
/// idle device can't drag them back below the gate. Everything else in the
/// payload is per-user, not per-device, so picking a winner loses nothing.
List<PresentMember> mergePresence(
  Iterable<Map<String, dynamic>> payloads, {
  DateTime Function()? now,
}) {
  final clock = now ?? DateTime.now;
  final byUser = <String, PresentMember>{};
  final privateEverywhere = <String, bool>{};
  for (final p in payloads) {
    final uid = p['user_id'] as String?;
    if (uid == null) continue;
    final private = p['privacy_mode'] as bool? ?? false;
    privateEverywhere[uid] = (privateEverywhere[uid] ?? true) && private;
    final member = PresentMember(
      userId: uid,
      displayName: p['display_name'] as String? ?? 'Watcher',
      avatarUrl: p['avatar_url'] as String?,
      role: p['role'] as String? ?? 'member',
      joinedAt: DateTime.tryParse(p['joined_at'] as String? ?? '') ?? clock(),
      readyStatus: ReadyStatus.fromWire(p['ready_status'] as String?),
      loadedFileName: p['loaded_file_name'] as String?,
      loadedDuration: switch (p['loaded_duration_ms']) {
        final num ms when ms > 0 => Duration(milliseconds: ms.toInt()),
        _ => null,
      },
      confirmedMedia: p['confirmed_media'] as String?,
      privacyMode: private,
    );
    final existing = byUser[uid];
    if (existing == null || member.readyStatus.index > existing.readyStatus.index) {
      byUser[uid] = member;
    }
  }
  return [
    for (final entry in byUser.entries)
      entry.value.withPrivacyMode(privateEverywhere[entry.key] ?? false),
  ]..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
}

/// Last-action-wins ordering, and the monotonic stamp that makes it work.
class SyncOrdering {
  SyncOrdering({required this.userId, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final String userId;
  final DateTime Function() _now;

  int _lastIssued = 0;
  int _lastApplied = 0;

  int get lastApplied => _lastApplied;

  /// Strictly increasing per sender. [shouldApply] drops anything with
  /// `timestamp <= lastApplied`, and a wall-clock millisecond is not
  /// fine-grained enough: `_playPause` broadcasts play *and* seek in one
  /// synchronous block, so both stamped `DateTime.now()` and receivers silently
  /// dropped the second one. Every broadcast must stamp itself from here.
  int nextTimestamp() {
    final now = _now().millisecondsSinceEpoch;
    _lastIssued = now > _lastIssued ? now : _lastIssued + 1;
    return _lastIssued;
  }

  bool shouldApply(Map<String, dynamic> payload) {
    final senderId = payload['senderId'] as String;
    final timestamp = payload['timestamp'] as int;
    // self:false should exclude own events; defensive double-check.
    if (senderId == userId) return false;
    if (timestamp <= _lastApplied) return false;
    _lastApplied = timestamp;
    return true;
  }
}

bool presencePayloadsMatch(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

class TrailingThrottle<T> {
  TrailingThrottle({
    this.interval = const Duration(milliseconds: 250),
    this.maxCalls,
    this.window = const Duration(milliseconds: 250),
    this.equals,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? schedule,
  }) : _now = now ?? DateTime.now,
       _schedule = schedule ?? Timer.new;

  final Duration interval;
  final int? maxCalls;
  final Duration window;
  final bool Function(T, T)? equals;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _schedule;

  final _sendTimes = <int>[];
  Timer? _flushTimer;
  T? _queued;
  bool _hasQueued = false;
  T? _lastSent;
  bool _hasSent = false;
  bool _waiveSpacing = false;
  bool _disposed = false;

  bool get hasPending => _hasQueued;

  int _deferralMs(int now) {
    _sendTimes.removeWhere((t) => now - t >= window.inMilliseconds);
    var wait = 0;
    if (_sendTimes.isNotEmpty && !_waiveSpacing) {
      final spacing = interval.inMilliseconds - (now - _sendTimes.last);
      if (spacing > wait) wait = spacing;
    }
    final budget = maxCalls;
    if (budget != null && _sendTimes.length >= budget) {
      final freeAt = window.inMilliseconds - (now - _sendTimes.first);
      if (freeAt > wait) wait = freeAt;
    }
    return wait;
  }

  bool _isRedundant(T value) => _hasSent && (equals?.call(_lastSent as T, value) ?? false);

  void _emit(T value, int now, void Function(T) send) {
    _waiveSpacing = false;
    _sendTimes.add(now);
    _lastSent = value;
    _hasSent = true;
    send(value);
  }

  void submit(T value, void Function(T) send) {
    if (_disposed) return;
    if (_isRedundant(value)) {
      discardPending();
      return;
    }
    final now = _now().millisecondsSinceEpoch;
    final wait = _deferralMs(now);
    if (wait <= 0) {
      _emit(value, now, send);
      return;
    }
    _queued = value;
    _hasQueued = true;
    if (_flushTimer?.isActive ?? false) return;
    _flushTimer = _schedule(Duration(milliseconds: wait), () => _flush(send));
  }

  void _flush(void Function(T) send) {
    if (!_hasQueued) return;
    final queued = _queued as T;
    _queued = null;
    _hasQueued = false;
    if (_disposed) return;
    if (_isRedundant(queued)) return;
    final now = _now().millisecondsSinceEpoch;
    _deferralMs(now);
    _emit(queued, now, send);
  }

  void discardPending() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _queued = null;
    _hasQueued = false;
  }

  void renew() {
    discardPending();
    _lastSent = null;
    _hasSent = false;
    _waiveSpacing = true;
  }

  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
  }
}

typedef ReactionThrottle = TrailingThrottle<String>;

// ---------------------------------------------------------------------------
// Position heartbeat and stall recovery
// ---------------------------------------------------------------------------

/// Transit compensation is capped: a broadcast that claims to be older than
/// this is either a skewed clock or a stale redelivery, and extrapolating it
/// would overshoot the room rather than meet it.
const kMaxPositionLead = Duration(seconds: 5);

/// Where a playing sender *is now*, given where it was when it sent.
///
/// `sentAtMs`/`nowMs` are both server-corrected clocks, so skew between the two
/// devices cancels out. A paused sender does not move, and a message without a
/// send time (an older client) is taken at face value.
Duration extrapolatePosition(
  Duration position, {
  required bool playing,
  required int? sentAtMs,
  required int nowMs,
}) {
  if (!playing || sentAtMs == null) return position;
  final elapsed = (nowMs - sentAtMs).clamp(0, kMaxPositionLead.inMilliseconds);
  return position + Duration(milliseconds: elapsed);
}

/// Whether this client should send the 10 s position heartbeat.
///
/// Authority, not host: a host who quit without leaving keeps the role, and a
/// host-only heartbeat left that room with no drift correction at all. A
/// stalled sender stays quiet, because its frozen position would drag every
/// member who kept playing *back* to it - the stalled one catches up instead.
/// [catchUpPending] covers the moment just after a stall, when our position is
/// still behind and the answer that moves us forward is in flight.
bool shouldSendHeartbeat({
  required bool isAuthority,
  required bool playing,
  required bool buffering,
  required bool applyingRemote,
  required bool catchUpPending,
}) => isAuthority && playing && !buffering && !applyingRemote && !catchUpPending;

/// Stalls shorter than this are routine decoder hiccups, not lost time.
const kMinStallForCatchUp = Duration(milliseconds: 400);

/// A flapping connection stalls repeatedly; one catch-up per window is plenty,
/// and the heartbeat covers anything that slips between them.
const kBufferCatchUpCooldown = Duration(seconds: 3);

/// Whether a stall that just ended is worth asking the room where it is.
bool shouldCatchUpAfterStall({required Duration stall, required Duration? sinceLastCatchUp}) {
  if (stall < kMinStallForCatchUp) return false;
  return sinceLastCatchUp == null || sinceLastCatchUp >= kBufferCatchUpCooldown;
}
