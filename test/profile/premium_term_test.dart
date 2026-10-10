import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/subscription_screen.dart';

void main() {
  final now = DateTime.utc(2026, 9, 26);

  group('premiumTermFrom', () {
    test('a live web row is paid through its period end', () {
      final term = premiumTermFrom(
        subscription: {
          'tier': 'premium',
          'source': 'creem',
          'current_period_end': '2026-10-20T00:00:00Z',
        },
        now: now,
      );
      expect(term?.source, 'web');
      expect(term?.until, DateTime.utc(2026, 10, 20));
      expect(term?.renews, isNull);
    });

    test('a manual or debug row is a manual grant', () {
      final term = premiumTermFrom(
        subscription: {
          'tier': 'premium',
          'source': 'debug',
          'current_period_end': '2026-10-20T00:00:00Z',
        },
        now: now,
      );
      expect(term?.source, 'manual');
    });

    test('any seller of record is the web rail, not just one provider', () {
      for (final source in ['creem', 'acme']) {
        final term = premiumTermFrom(
          subscription: {
            'tier': 'premium',
            'source': source,
            'current_period_end': '2026-10-20T00:00:00Z',
          },
          now: now,
        );
        expect(term?.source, 'web', reason: source);
        expect(premiumTermLabel(term), startsWith('PAID THROUGH'));
      }
    });

    test('expired, revoked and free rows are ignored', () {
      expect(
        premiumTermFrom(
          subscription: {
            'tier': 'free',
            'source': 'creem',
            'current_period_end': '2026-10-20T00:00:00Z',
          },
          apple: [
            {'expires_at': '2026-09-01T00:00:00Z', 'revoked_at': null, 'auto_renew': true},
            {
              'expires_at': '2026-12-01T00:00:00Z',
              'revoked_at': '2026-09-20T00:00:00Z',
              'auto_renew': true,
            },
          ],
          now: now,
        ),
        isNull,
      );
    });

    test('the later of two rails wins, carrying its renewal flag', () {
      final term = premiumTermFrom(
        subscription: {
          'tier': 'premium',
          'source': 'creem',
          'current_period_end': '2026-10-20T00:00:00Z',
        },
        apple: [
          {'expires_at': '2026-11-02T00:00:00Z', 'revoked_at': null, 'auto_renew': false},
        ],
        now: now,
      );
      expect(term?.source, 'apple');
      expect(term?.renews, isFalse);
    });
  });

  group('premiumTermLabel', () {
    final until = DateTime(2026, 10, 20, 12);

    test('only a proven App Store renewal says renews', () {
      expect(
        premiumTermLabel(PremiumTerm(until: until, source: 'apple', renews: true)),
        'RENEWS 20 OCT 2026',
      );
      expect(
        premiumTermLabel(PremiumTerm(until: until, source: 'apple', renews: false)),
        'ENDS 20 OCT 2026',
      );
      expect(
        premiumTermLabel(PremiumTerm(until: until, source: 'web')),
        'PAID THROUGH 20 OCT 2026',
      );
      expect(
        premiumTermLabel(PremiumTerm(until: until, source: 'manual')),
        'PATRON UNTIL 20 OCT 2026',
      );
      expect(premiumTermLabel(null), isNull);
    });
  });
}
