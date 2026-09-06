import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/updates/appcast.dart';

const kAppcastUrl =
    'https://github.com/shubhamsinghshubham777/synctogether/releases/latest/download/appcast.xml';

const _kAutoDownloadKey = 'pt.auto_download_updates';

class UpdateService extends ChangeNotifier {
  UpdateService._();

  static final instance = UpdateService._();

  String? _availableVersion;
  String? get availableVersion => _availableVersion;

  String? _currentVersion;
  String? get currentVersion => _currentVersion;

  String? _downloadUrl;
  String? get downloadUrl => _downloadUrl;

  String? _downloadedFilePath;
  String? get downloadedFilePath => _downloadedFilePath;

  bool _dismissed = false;
  bool _autoDownload = true;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _isDownloaded = false;
  bool _isInstalling = false;

  bool get autoDownload => _autoDownload;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  bool get isDownloaded => _isDownloaded;
  bool get isInstalling => _isInstalling;

  /// True when the updater is busy downloading or installing.
  bool get handingOff => _isDownloading || _isInstalling;

  bool get hasUpdate => _availableVersion != null && !_dismissed;

  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    notifyListeners();
  }

  Future<bool> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoDownload = prefs.getBool(_kAutoDownloadKey) ?? true;
      notifyListeners();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading the auto-download preference');
    }
    return _autoDownload;
  }

  Future<void> setAutoDownload(bool value) async {
    if (_autoDownload == value) return;
    _autoDownload = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAutoDownloadKey, value);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'saving the auto-download preference');
    }
    if (value && hasUpdate && !_isDownloaded && !_isDownloading) {
      unawaited(downloadUpdate());
    }
  }

  Future<void> checkForUpdate() async {
    if (!supportsSelfUpdate) return;
    await loadSettings();
    String? current;
    try {
      current = (await PackageInfo.fromPlatform()).version;
      _currentVersion = current;
      final release = await _fetchLatestRelease();
      if (release == null) return;
      final newer = compareVersions(release.version, current) > 0;
      trace(
        'update check finished',
        category: 'updates',
        data: {'current': current, 'latest': release.version, 'newer': newer},
      );
      if (!newer) return;
      _availableVersion = release.version;
      _downloadUrl = release.enclosureUrl;
      notifyListeners();

      if (_autoDownload && !_isDownloaded && !_isDownloading) {
        unawaited(downloadUpdate());
      }
    } on SocketException catch (e) {
      trace('update check offline', category: 'updates', data: {'error': '$e'});
    } on HandshakeException catch (e) {
      trace('update check tls failure', category: 'updates', data: {'error': '$e'});
    } on TimeoutException catch (e) {
      trace('update check timed out', category: 'updates', data: {'error': '$e'});
    } catch (e, s) {
      reportNonFatal(e, s, during: 'checking for an app update (current $current)');
    }
  }

  Future<bool> downloadUpdate() async {
    if (!supportsSelfUpdate || _isDownloading || _downloadUrl == null) return false;
    _isDownloading = true;
    _downloadProgress = 0.0;
    notifyListeners();

    final ext = Platform.isWindows ? 'exe' : 'dmg';
    final targetFile = File(
      '${Directory.systemTemp.path}/synctogether-update-$_availableVersion.$ext',
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

    try {
      if (await targetFile.exists() && await targetFile.length() > 0) {
        _downloadedFilePath = targetFile.path;
        _isDownloaded = true;
        _isDownloading = false;
        _downloadProgress = 1.0;
        notifyListeners();
        return true;
      }

      final request = await client.getUrl(Uri.parse(_downloadUrl!));
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException(
          'download failed with status ${response.statusCode}',
          uri: Uri.parse(_downloadUrl!),
        );
      }

      final contentLength = response.contentLength;
      final sink = targetFile.openWrite();
      var receivedBytes = 0;
      var lastNotified = DateTime.now();

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (contentLength > 0) {
          _downloadProgress = (receivedBytes / contentLength).clamp(0.0, 1.0);
          final now = DateTime.now();
          if (now.difference(lastNotified).inMilliseconds > 150) {
            lastNotified = now;
            notifyListeners();
          }
        }
      }
      await sink.flush();
      await sink.close();

      _downloadedFilePath = targetFile.path;
      _isDownloaded = true;
      _isDownloading = false;
      _downloadProgress = 1.0;
      trace(
        'update downloaded silently',
        category: 'updates',
        data: {'path': targetFile.path, 'bytes': receivedBytes},
      );
      notifyListeners();
      return true;
    } catch (e, s) {
      _isDownloading = false;
      _downloadProgress = 0.0;
      reportNonFatal(e, s, during: 'downloading update $_availableVersion');
      notifyListeners();
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> installAndRestart() async {
    if (!supportsSelfUpdate || _isInstalling) return false;

    if (!_isDownloaded || _downloadedFilePath == null) {
      final downloaded = await downloadUpdate();
      if (!downloaded || _downloadedFilePath == null) {
        return false;
      }
    }

    _isInstalling = true;
    notifyListeners();

    try {
      trace(
        'starting silent desktop update',
        category: 'updates',
        data: {
          'from': _currentVersion,
          'to': _availableVersion,
          'platform': defaultTargetPlatform.name,
        },
      );

      if (Platform.isWindows) {
        await Process.start(_downloadedFilePath!, [
          '/VERYSILENT',
          '/SP-',
          '/NORESTARTAPPLICATIONS',
        ], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        final bundlePath = _resolveMacosBundlePath();
        final scriptFile = File('${Directory.systemTemp.path}/synctogether_silent_update.sh');
        await scriptFile.writeAsString('''#!/bin/sh
DMG_PATH="\$1"
TARGET_APP="\$2"
PID="\$3"

MOUNT_DIR=\$(mktemp -d /tmp/synctogether_mount.XXXXXX)
hdiutil attach "\$DMG_PATH" -nobrowse -readonly -mountpoint "\$MOUNT_DIR" -quiet

while kill -0 "\$PID" 2>/dev/null; do
  sleep 0.1
done

ditto "\$MOUNT_DIR/SyncTogether.app" "\$TARGET_APP"

hdiutil detach "\$MOUNT_DIR" -force -quiet
rm -rf "\$MOUNT_DIR"
rm -f "\$DMG_PATH"

open -n "\$TARGET_APP"
''');
        await Process.run('chmod', ['+x', scriptFile.path]);
        await Process.start('/bin/sh', [
          scriptFile.path,
          _downloadedFilePath!,
          bundlePath,
          pid.toString(),
        ], mode: ProcessStartMode.detached);
      }

      await Analytics.instance.flush().timeout(const Duration(seconds: 2), onTimeout: () {});
      exit(0);
    } catch (e, s) {
      _isInstalling = false;
      reportNonFatal(e, s, during: 'silent install and restart');
      notifyListeners();
      return false;
    }
  }

  static String _resolveMacosBundlePath() {
    final execPath = Platform.resolvedExecutable;
    const marker = '.app';
    final idx = execPath.indexOf(marker);
    if (idx != -1) {
      return execPath.substring(0, idx + marker.length);
    }
    return '/Applications/SyncTogether.app';
  }

  Future<AppcastRelease?> _fetchLatestRelease() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(kAppcastUrl));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException(
          'appcast fetch returned ${response.statusCode}',
          uri: Uri.parse(kAppcastUrl),
        );
      }
      final osName = Platform.isWindows ? 'windows' : 'macos';
      var release = newestReleaseForPlatform(body, osName);
      if (release == null) {
        final ver = newestVersionIn(body);
        if (ver != null) {
          final ext = Platform.isWindows ? 'exe' : 'dmg';
          final platformSuffix = Platform.isWindows ? 'Windows' : 'macOS';
          final fallbackUrl =
              'https://github.com/shubhamsinghshubham777/synctogether/releases/download/v$ver/SyncTogether-$ver-$platformSuffix.$ext';
          release = AppcastRelease(version: ver, enclosureUrl: fallbackUrl, os: osName);
        }
      }
      return release;
    } finally {
      client.close(force: true);
    }
  }
}
