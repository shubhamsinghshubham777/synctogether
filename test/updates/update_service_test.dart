import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctogether/updates/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UpdateService', () {
    test('initial state has default values', () {
      final updates = UpdateService.instance;
      expect(updates.isDownloading, isFalse);
      expect(updates.isDownloaded, isFalse);
      expect(updates.isInstalling, isFalse);
      expect(updates.handingOff, isFalse);
      expect(updates.downloadProgress, 0.0);
    });

    test('loadSettings and setAutoDownload persist preference', () async {
      final updates = UpdateService.instance;
      await updates.loadSettings();
      expect(updates.autoDownload, isTrue);

      await updates.setAutoDownload(false);
      expect(updates.autoDownload, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pt.auto_download_updates'), isFalse);

      await updates.setAutoDownload(true);
      expect(updates.autoDownload, isTrue);
      expect(prefs.getBool('pt.auto_download_updates'), isTrue);
    });

    test('dismiss hides update banner', () {
      final updates = UpdateService.instance;
      expect(updates.hasUpdate, isFalse);
      updates.dismiss();
      expect(updates.hasUpdate, isFalse);
    });
  });
}
