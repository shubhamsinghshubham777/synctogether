import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/microsoft_iap_service.dart';

class _FakeStore implements StorePurchaseChannel {
  _FakeStore({this.key = 'key.jwt', this.result = const StorePurchaseResult('succeeded')});
  final String key;
  final StorePurchaseResult result;
  final calls = <String>[];

  @override
  Future<String> idKey({required String serviceTicket, required String userId}) async {
    calls.add('idKey:$serviceTicket:$userId');
    return key;
  }

  @override
  Future<List<MicrosoftProduct>> products() async => const [];

  @override
  Future<StorePurchaseResult> purchase(String storeId) async {
    calls.add('purchase:$storeId');
    return result;
  }
}

MicrosoftIapService _service(
  _FakeStore store,
  Map<String, ({int status, String? error, Object? data})> answers, {
  String? userId = 'user-1',
}) => MicrosoftIapService.forTesting(
  channel: store,
  invoke: (path, body) async => answers[path] ?? (status: 500, error: null, data: null),
  userId: () => userId,
);

void main() {
  group('classifyMicrosoftVerify', () {
    test('maps the server answers to notices', () {
      expect(classifyMicrosoftVerify(200, null), MicrosoftIapNotice.activated);
      expect(
        classifyMicrosoftVerify(404, 'nothing_to_restore'),
        MicrosoftIapNotice.nothingToRestore,
      );
      expect(classifyMicrosoftVerify(409, 'owned_elsewhere'), MicrosoftIapNotice.ownedElsewhere);
      expect(classifyMicrosoftVerify(403, 'account_mismatch'), MicrosoftIapNotice.ownedElsewhere);
      expect(classifyMicrosoftVerify(500, 'server_error'), MicrosoftIapNotice.failed);
    });

    test('a recorded but no longer live subscription is not an activation', () {
      expect(classifyMicrosoftVerify(200, null, active: true), MicrosoftIapNotice.activated);
      expect(
        classifyMicrosoftVerify(200, null, active: false),
        MicrosoftIapNotice.nothingToRestore,
      );
    });
  });

  group('MicrosoftProduct.tryParse', () {
    test('reads the native answer and refuses a row without a store id', () {
      final p = MicrosoftProduct.tryParse({
        'storeId': '0010',
        'title': 'Monthly',
        'price': r'$3.99',
        'period': 'month',
      });
      expect(p?.storeId, '0010');
      expect(p?.annual, isFalse);
      expect(p?.currency, '');
      expect(MicrosoftProduct.tryParse({'title': 'x'}), isNull);
      expect(MicrosoftProduct.tryParse('nope'), isNull);
    });

    test('carries the currency the Store prices in', () {
      expect(MicrosoftProduct.tryParse({'storeId': '0010', 'currency': 'PKR'})?.currency, 'PKR');
    });
  });

  group('StorePurchaseResult', () {
    test('reads the native answer, and an unreadable one is a server error', () {
      final r = StorePurchaseResult.parse({'status': 'notPurchased', 'hresult': -2147023673});
      expect(r.status, 'notPurchased');
      expect(r.hresult, -2147023673);
      expect(r.hresultHex, '0x800704c7');
      expect(StorePurchaseResult.parse('succeeded').status, 'serverError');
      expect(StorePurchaseResult.parse(null).status, 'serverError');
      expect(StorePurchaseResult.parse({'status': 'succeeded'}).hresult, 0);
    });

    test('only a refusal is reported: a closed dialog stays quiet', () {
      bool report(String status, [int hresult = 0]) =>
          storePurchaseNeedsReport(StorePurchaseResult(status, hresult: hresult));
      expect(report('succeeded'), isFalse);
      expect(report('alreadyPurchased'), isFalse);
      expect(report('networkError'), isFalse);
      expect(report('notPurchased'), isFalse);
      expect(report('notPurchased', -2147023673), isTrue);
      expect(report('serverError'), isTrue);
      expect(report('somethingNew'), isTrue);
    });
  });

  group('buy', () {
    const product = MicrosoftProduct(
      storeId: '0010',
      title: 'Monthly',
      price: 'PKR 1,000',
      period: 'month',
      currency: 'PKR',
    );

    test('a closed dialog makes no verify call and raises no notice', () async {
      final store = _FakeStore(result: const StorePurchaseResult('notPurchased'));
      final service = _service(store, const {});
      final notices = <MicrosoftIapNotice>[];
      final sub = service.notices.listen(notices.add);
      await service.buy(product);
      await Future<void>.delayed(Duration.zero);
      expect(store.calls, ['purchase:0010']);
      expect(notices, isEmpty);
      await sub.cancel();
    });

    test('a network error tells the person without asking the server', () async {
      final store = _FakeStore(result: const StorePurchaseResult('networkError'));
      final service = _service(store, const {});
      final notices = <MicrosoftIapNotice>[];
      final sub = service.notices.listen(notices.add);
      await service.buy(product);
      await Future<void>.delayed(Duration.zero);
      expect(store.calls, ['purchase:0010']);
      expect(notices, [MicrosoftIapNotice.failed]);
      await sub.cancel();
    });
  });

  group('sync', () {
    test('mints the key for the signed-in account and activates', () async {
      final store = _FakeStore();
      final service = _service(store, {
        'ms-iap/ticket': (status: 200, error: null, data: {'service_ticket': 'T'}),
        'ms-iap/verify': (status: 200, error: null, data: {'outcome': 'applied'}),
      });
      expect(await service.sync(silent: true), MicrosoftIapNotice.activated);
      expect(store.calls, ['idKey:T:user-1']);
    });

    test('a cancelled subscription is reported as nothing to restore', () async {
      final service = _service(_FakeStore(), {
        'ms-iap/ticket': (status: 200, error: null, data: {'service_ticket': 'T'}),
        'ms-iap/verify': (status: 200, error: null, data: {'outcome': 'applied', 'active': false}),
      });
      expect(await service.sync(silent: true), MicrosoftIapNotice.nothingToRestore);
    });

    test('a missing ticket or key fails without asking the server to verify', () async {
      final noTicket = _service(_FakeStore(), {
        'ms-iap/ticket': (status: 500, error: null, data: null),
      });
      expect(await noTicket.sync(silent: true), MicrosoftIapNotice.failed);

      final noKey = _service(_FakeStore(key: ''), {
        'ms-iap/ticket': (status: 200, error: null, data: {'service_ticket': 'T'}),
      });
      expect(await noKey.sync(silent: true), MicrosoftIapNotice.failed);
    });

    test('signed out does nothing', () async {
      final store = _FakeStore();
      final service = _service(store, const {}, userId: null);
      expect(await service.sync(silent: true), MicrosoftIapNotice.failed);
      expect(store.calls, isEmpty);
    });
  });

  group('premiumTermFrom', () {
    final now = DateTime.utc(2026, 10, 15);
    test('a Microsoft row is its own rail and carries auto-renew', () {
      final term = premiumTermFrom(
        microsoft: [
          {'expires_at': '2026-11-15T00:00:00Z', 'revoked_at': null, 'auto_renew': true},
        ],
        now: now,
      );
      expect(term?.source, 'microsoft');
      expect(term?.renews, isTrue);
    });

    test('a revoked or expired row is no term', () {
      expect(
        premiumTermFrom(
          microsoft: [
            {'expires_at': '2026-11-15T00:00:00Z', 'revoked_at': '2026-10-01T00:00:00Z'},
            {'expires_at': '2026-10-01T00:00:00Z', 'revoked_at': null},
          ],
          now: now,
        ),
        isNull,
      );
    });
  });
}
