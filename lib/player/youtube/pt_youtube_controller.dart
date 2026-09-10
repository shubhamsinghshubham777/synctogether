import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/platform.dart';

enum PTYtPlayerState { unknown, unstarted, ended, playing, paused, buffering, cued }

PTYtPlayerState _stateFromCode(num? code) => switch (code?.toInt()) {
  -1 => PTYtPlayerState.unstarted,
  0 => PTYtPlayerState.ended,
  1 => PTYtPlayerState.playing,
  2 => PTYtPlayerState.paused,
  3 => PTYtPlayerState.buffering,
  5 => PTYtPlayerState.cued,
  _ => PTYtPlayerState.unknown,
};

const _kReadyDeadline = Duration(seconds: 20);
const _kSeekPositionHold = Duration(milliseconds: 400);

class PTYouTubeController extends ChangeNotifier {
  PTYouTubeController(this._videoId) {
    unawaited(_serve());
  }

  String _videoId;
  String get videoId => _videoId;

  String? _servedVideoId;

  HttpServer? _server;
  InAppWebViewController? _web;
  Timer? _readyDeadline;
  bool _disposed = false;
  bool _pageRequested = false;
  bool _commandFailureReported = false;
  DateTime _positionHoldUntil = DateTime.fromMillisecondsSinceEpoch(0);

  Uri? _pageUrl;
  Uri? get pageUrl => _pageUrl;

  /// Non-null on macOS Store builds where no loopback server is used.
  /// The embed widget uses this to load the WebView via [InAppWebViewInitialData]
  /// with [inlineDataBaseUrl] as the document origin instead of a real URL.
  String? _initialHtml;
  String? get initialHtml => _initialHtml;

  /// The synthetic origin used for inline-data WebViews on macOS Store builds.
  /// Must match the `origin` parameter in the YouTube IFrame `playerVars` and
  /// must be in the Turnstile widget's hostname allow-list.
  static const inlineDataBaseUrl = 'http://localhost';

  bool _isReady = false;
  bool get isReady => _isReady;

  bool _isAdPlaying = false;
  bool get isAdPlaying => _isAdPlaying;
  Duration? _pendingSeekWhileAd;

  PTYtPlayerState _playerState = .unknown;
  PTYtPlayerState get playerState => _playerState;

  Duration _position = Duration.zero;
  Duration get position => _position;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  int? _errorCode;
  int? get errorCode => _errorCode;
  bool get hasError => _errorCode != null;

  int _volume = 100;

  Future<void> _serve() async {
    if (!useLoopbackServer) {
      // macOS Store build: no HttpServer allowed under the App Sandbox without
      // the network.server entitlement. WKWebView on macOS correctly honours
      // InAppWebViewInitialData.baseUrl, so serve the page as inline data.
      _initialHtml = _pageHtml(null, _videoId);
      _armReadyDeadline();
      notifyListeners();
      return;
    }
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (_disposed) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen((request) {
        if (request.uri.path != '/') {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
          return;
        }
        _pageRequested = true;
        _servedVideoId = _videoId;
        trace('player page requested', category: 'youtube');
        request.response
          ..headers.contentType = ContentType.html
          ..write(_pageHtml(server.port, _videoId));
        request.response.close();
      });
      _pageUrl = Uri.parse('http://localhost:${server.port}/');
      trace('serving player', category: 'youtube', data: {'url': '$_pageUrl'});
      _armReadyDeadline();
      notifyListeners();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'starting the YouTube loopback server');
    }
  }

  void _armReadyDeadline() {
    _readyDeadline?.cancel();
    _readyDeadline = Timer(_kReadyDeadline, () {
      if (_disposed || _isReady) return;
      reportNonFatal(
        StateError(
          'The YouTube embed was not ready after ${_kReadyDeadline.inSeconds}s '
          '(webview attached: ${_web != null}, page requested: $_pageRequested)',
        ),
        StackTrace.current,
        during: 'loading the YouTube player',
      );
    });
  }

  void attach(InAppWebViewController web) {
    _web = web;
    web.addJavaScriptHandler(handlerName: 'ytReady', callback: _onReady);
    web.addJavaScriptHandler(handlerName: 'ytState', callback: _onStateChange);
    web.addJavaScriptHandler(handlerName: 'ytTick', callback: _onTick);
    web.addJavaScriptHandler(handlerName: 'ytError', callback: _onError);
    web.addJavaScriptHandler(handlerName: 'ytAdState', callback: _onAdState);
  }

  Map<String, dynamic> _payload(List<dynamic> args) {
    if (args.isEmpty) return const {};
    final first = args.first;
    return first is Map ? first.cast<String, dynamic>() : const {};
  }

  void _onReady(List<dynamic> args) {
    if (_disposed) return;
    _readyDeadline?.cancel();
    _isReady = true;
    final data = _payload(args);
    if (data['state'] != null) {
      _playerState = _stateFromCode(data['state'] as num?);
    }
    if (_playerState == .unknown) {
      _playerState = .unstarted;
    }
    _applySnapshot(data);
    trace(
      'player ready',
      category: 'youtube',
      data: {'videoId': _videoId, 'state': _playerState.name, 'isAd': _isAdPlaying},
    );
    _push('ptVolume($_volume)');
    if (_servedVideoId != null && _servedVideoId != _videoId) {
      _push("ptLoad('$_videoId')");
    }
    notifyListeners();
  }

  void _onStateChange(List<dynamic> args) {
    if (_disposed) return;
    final data = _payload(args);
    _playerState = _stateFromCode(data['state'] as num?);
    _applySnapshot(data);
    notifyListeners();
  }

  void _onTick(List<dynamic> args) {
    if (_disposed) return;
    final before = (_position, _duration);
    _applySnapshot(_payload(args));
    if (before != (_position, _duration)) notifyListeners();
  }

  bool _debugSimulatedAd = false;
  bool get debugSimulatedAd => _debugSimulatedAd;

  void _onAdState(List<dynamic> args) {
    if (_disposed) return;
    final data = _payload(args);
    // When debug simulated ad is active, prevent real iframe tick from cancelling it.
    if (_debugSimulatedAd && data['isAd'] == false) {
      return;
    }
    final isAd = data['isAd'] == true;
    if (_isAdPlaying != isAd) {
      _isAdPlaying = isAd;
      trace('youtube ad state changed', category: 'youtube', data: {'isAd': isAd});
      if (!_isAdPlaying && _pendingSeekWhileAd != null) {
        final seek = _pendingSeekWhileAd!;
        _pendingSeekWhileAd = null;
        seekTo(seek);
      }
      notifyListeners();
    }
  }

  /// Toggle simulated ad playback in debug builds for manual and automated testing.
  void debugToggleAdState() {
    assert(kDebugMode, 'debugToggleAdState must only be called in debug mode');
    _debugSimulatedAd = !_debugSimulatedAd;
    if (_debugSimulatedAd) {
      pause();
    } else {
      play();
    }
    _onAdState([
      {'isAd': _debugSimulatedAd},
    ]);
  }

  void _onError(List<dynamic> args) {
    if (_disposed) return;
    _errorCode = (_payload(args)['code'] as num?)?.toInt() ?? -1;
    notifyListeners();
  }

  void _applySnapshot(Map<String, dynamic> data) {
    if (!_debugSimulatedAd) {
      final isAd = data['isAd'] == true;
      if (isAd != _isAdPlaying) {
        _isAdPlaying = isAd;
      }
    }
    if (data['state'] != null) {
      _playerState = _stateFromCode(data['state'] as num?);
    }
    if (_isAdPlaying) {
      // While an ad is active, the snapshot carries the ad's duration and
      // position. Do not overwrite the main video's position or duration.
      return;
    }
    final seconds = (data['duration'] as num?)?.toDouble() ?? 0;
    if (seconds > 0) _duration = Duration(milliseconds: (seconds * 1000).round());
    if (DateTime.now().isBefore(_positionHoldUntil)) return;
    final at = (data['position'] as num?)?.toDouble() ?? 0;
    _position = Duration(milliseconds: (at * 1000).round());
  }

  void play() => _push('ptPlay()');

  void pause() => _push('ptPause()');

  void seekTo(Duration position) {
    if (_disposed) return;
    if (_isAdPlaying) {
      _pendingSeekWhileAd = position;
      return;
    }
    _position = position;
    _positionHoldUntil = DateTime.now().add(_kSeekPositionHold);
    _push('ptSeek(${position.inMilliseconds / 1000})');
    notifyListeners();
  }

  void setVolume(int volume) {
    _volume = volume.clamp(0, 100);
    _push('ptVolume($_volume)');
  }

  void loadVideo(String videoId) {
    if (_disposed || videoId == _videoId) return;
    _videoId = videoId;
    _position = Duration.zero;
    _duration = Duration.zero;
    _errorCode = null;
    _isAdPlaying = false;
    _pendingSeekWhileAd = null;
    _playerState = .unstarted;
    _push("currentVideoId = '$videoId'; ptLoad('$videoId');");
    notifyListeners();
  }

  Future<void> _push(String js) async {
    final web = _web;
    if (web == null || _disposed) return;
    try {
      await web.evaluateJavascript(source: js);
    } catch (e, s) {
      if (_disposed || _commandFailureReported) return;
      _commandFailureReported = true;
      reportNonFatal(e, s, during: 'sending a command to the YouTube embed');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _readyDeadline?.cancel();
    _server?.close(force: true);
    _web = null;
    super.dispose();
  }

  // [port] is the loopback server's port for normal builds, or null for
  // macOS Store builds where the HTML is served as inline data. In the
  // inline-data case the origin is the fixed `inlineDataBaseUrl` value that
  // matches the InAppWebViewInitialData.baseUrl set by the embed widget.
  String _pageHtml(int? port, String videoId) {
    final origin = port != null ? 'http://localhost:$port' : inlineDataBaseUrl;
    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { margin: 0; padding: 0; height: 100%; background: transparent; overflow: hidden; }
  body { pointer-events: none; }
  #player, iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
</style>
</head>
<body>
<div id="player"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player = null;
var ready = false;
var ticker = null;
var currentVideoId = '$videoId';
var isAd = false;

function post(name, data) {
  var bridge = window.flutter_inappwebview;
  if (bridge && bridge.callHandler) { bridge.callHandler(name, data); }
}

function checkAdState() {
  if (!player) return false;
  try {
    if (typeof player.getAdState === 'function' && player.getAdState() === 1) {
      return true;
    }
    if (typeof player.getVideoData === 'function') {
      var vdata = player.getVideoData();
      if (vdata && vdata.video_id && vdata.video_id !== currentVideoId) {
        return true;
      }
    }
    var playerEl = document.getElementById('player');
    if (playerEl && playerEl.classList && playerEl.classList.contains('ad-showing')) {
      return true;
    }
  } catch (e) {}
  return false;
}

function snapshot() {
  if (!player || !player.getCurrentTime) {
    return { position: 0, duration: 0, state: -1, isAd: false };
  }
  var adActive = checkAdState();
  return {
    position: player.getCurrentTime() || 0,
    duration: player.getDuration() || 0,
    state: (typeof player.getPlayerState === 'function') ? player.getPlayerState() : -1,
    isAd: adActive
  };
}

function onYouTubeIframeAPIReady() {
  player = new YT.Player('player', {
    host: 'https://www.youtube.com',
    videoId: '$videoId',
    playerVars: {
      autoplay: 0,
      controls: 0,
      rel: 0,
      iv_load_policy: 3,
      disablekb: 1,
      playsinline: 1,
      modestbranding: 1,
      fs: 0,
      cc_load_policy: 1,
      cc_lang_pref: 'en',
      vq: 'hd1080',
      enablejsapi: 1,
      origin: '$origin'
    },
    events: {
      onReady: function () {
        ready = true;
        post('ytReady', snapshot());
        startTicker();
      },
      onStateChange: function (event) {
        var data = snapshot();
        data.state = event.data;
        post('ytState', data);
      },
      onApiChange: function () {
        var snap = snapshot();
        var nowAd = snap.isAd;
        if (nowAd !== isAd) {
          isAd = nowAd;
          document.body.style.pointerEvents = isAd ? 'auto' : 'none';
          post('ytAdState', { isAd: isAd });
        }
      },
      onError: function (event) {
        post('ytError', { code: event.data });
      }
    }
  });
}

function startTicker() {
  if (ticker) { return; }
  ticker = setInterval(function () {
    var snap = snapshot();
    post('ytTick', snap);
    var nowAd = snap.isAd;
    if (nowAd !== isAd) {
      isAd = nowAd;
      document.body.style.pointerEvents = isAd ? 'auto' : 'none';
      post('ytAdState', { isAd: isAd });
    }
  }, 250);
}

function ptPlay() { if (ready) { player.playVideo(); } }
function ptPause() { if (ready) { player.pauseVideo(); } }
function ptSeek(seconds) { if (ready) { player.seekTo(seconds, true); } }
function ptVolume(level) { if (ready) { player.setVolume(level); } }
function ptLoad(id) {
  if (ready) {
    currentVideoId = id;
    player.cueVideoById({ videoId: id, suggestedQuality: 'hd1080' });
  }
}
</script>
</body>
</html>
''';
  }
}
