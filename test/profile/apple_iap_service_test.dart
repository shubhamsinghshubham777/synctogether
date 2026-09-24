import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/apple_iap_service.dart';

void main() {
  group('classifyVerifyResponse', () {
    test('an accepted transaction is finished and activates premium', () {
      expect(classifyVerifyResponse(200, null), (finish: true, notice: AppleIapNotice.activated));
    });

    test('a purchase bound to another account is finished, never retried forever', () {
      expect(classifyVerifyResponse(409, 'owned_elsewhere').finish, isTrue);
      expect(classifyVerifyResponse(403, 'account_mismatch').notice, AppleIapNotice.ownedElsewhere);
    });

    test('server and network failures leave the transaction for StoreKit to redeliver', () {
      expect(classifyVerifyResponse(500, 'server_error').finish, isFalse);
      expect(classifyVerifyResponse(401, 'not_authenticated').finish, isFalse);
      expect(classifyVerifyResponse(503, null).notice, AppleIapNotice.failed);
    });

    test('a refused transaction stays unfinished, since the server may be the one at fault', () {
      expect(classifyVerifyResponse(400, 'invalid_transaction'), (
        finish: false,
        notice: AppleIapNotice.failed,
      ));
    });
  });
}
