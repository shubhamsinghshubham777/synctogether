import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/subscription_screen.dart';

void main() {
  final now = DateTime.utc(2026, 9, 26);

  group('premiumTermFrom', () {
    test('a live Paddle row is paid through its period end', () {
      final term = premiumTermFrom(
        subscription: {
          'tier': 'premium',
          'source': 'paddle',
          'current_period_end': '2026-10-20T00:00:00Z',
        },
        now: now,
      );
      expect(term?.source, 'paddle');
      expect(term?.until, DateTime.utc(2026, 10, 20));
      expect(term?.renews, isNull);
    });

    test('a non-Paddle row is a manual grant', () {
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

    test('expired, revoked and free rows are ignored', () {
      expect(
        premiumTermFrom(
          subscription: {
            'tier': 'free',
            'source': 'paddle',
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
          'source': 'paddle',
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
        premiumTermLabel(PremiumTerm(until: until, source: 'paddle')),
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
