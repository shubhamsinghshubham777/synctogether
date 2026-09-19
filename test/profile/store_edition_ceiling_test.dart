import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/rooms/room_models.dart';

const _premium = TierLimits(
  tier: kPremiumTier,
  maxLiveRooms: 20,
  maxMembers: 16,
  maxSessionMinutes: 240,
  maxTotalSessionMinutes: 1440,
  avLevel: AvLevel.video,
  persistentRoomCap: 20,
  dormantHours: 24,
  freeExtensionMinutes: 0,
  mediaSharing: 'full',
);

const _guest = TierLimits(
  tier: kGuestTier,
  maxLiveRooms: 1,
  maxMembers: 4,
  maxSessionMinutes: 60,
  maxTotalSessionMinutes: 60,
  avLevel: AvLevel.none,
  persistentRoomCap: 0,
  dormantHours: 0,
  freeExtensionMinutes: 0,
);

void main() {
  group('applyStoreEditionCeiling', () {
    // Guideline 3.1.1 objects to the app *unlocking* content bought outside
    // it, so the store edition has to refuse the entitlement itself - hiding
    // the upsell is the shape Apple already rejected once.
    test('downgrades a premium entitlement to the free tier', () {
      final capped = applyStoreEditionCeiling(_premium, storeBuildOverride: true);

      expect(capped.tier, kFreeTier);
      expect(capped.isPremium, isFalse);
      expect(capped.avLevel, AvLevel.voice);
      expect(capped.maxMembers, 8);
      expect(capped.maxTotalSessionMinutes, 240);
      expect(capped.persistentRoomCap, 0);
      expect(capped.hasUnlimitedSharing, isFalse);
    });

    test('leaves premium intact off the store edition', () {
      expect(applyStoreEditionCeiling(_premium, storeBuildOverride: false).tier, kPremiumTier);
    });

    test('leaves a guest alone - guest is a floor, not a purchase', () {
      final capped = applyStoreEditionCeiling(_guest, storeBuildOverride: true);

      expect(capped.tier, kGuestTier);
      expect(capped.maxMembers, 4);
      expect(capped.avLevel, AvLevel.none);
    });

    test('leaves the free tier untouched', () {
      expect(
        applyStoreEditionCeiling(TierLimits.fallback, storeBuildOverride: true),
        same(TierLimits.fallback),
      );
    });
  });

  group('tierWearsCrown', () {
    // A crown is the one place another member's tier becomes visible, so the
    // store edition must answer no there too.
    test('no crowns on the store edition', () {
      expect(tierWearsCrown(kPremiumTier, storeBuildOverride: true), isFalse);
    });

    test('premium wears one everywhere else', () {
      expect(tierWearsCrown(kPremiumTier, storeBuildOverride: false), isTrue);
      expect(tierWearsCrown(kFreeTier, storeBuildOverride: false), isFalse);
      expect(tierWearsCrown(null, storeBuildOverride: false), isFalse);
    });
  });
}
