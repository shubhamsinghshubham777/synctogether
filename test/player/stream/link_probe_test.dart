import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/player/stream/link_probe.dart';

void main() {
  test('a link that finishes every sample inside a second is a reading when asked', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response..statusCode = HttpStatus.partialContent;
      res.add(List.filled(256 * 1024, 0));
      await res.close();
    });
    final url = Uri.parse('http://127.0.0.1:${server.port}/film');
    try {
      expect(await measureLinkBps(url: url, totalBytes: 100 << 20), isNull);
      final bps = await measureLinkBps(url: url, totalBytes: 100 << 20, allowShort: true);
      expect(bps, isNotNull);
      expect(bps, greaterThan(1e6));
    } finally {
      await server.close(force: true);
    }
  });
}
