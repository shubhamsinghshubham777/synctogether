/// How long Our Room keeps a shared film after the session that shared it ends,
/// as the app tells it to people.
///
/// These mirror `app_settings.our_room_media` (`free_hours` / `patron_hours`,
/// migration `20261109100000`), like the quota numbers in `EntitlementService`: the
/// server decides and enforces, this is only the wording. Change the setting and these
/// together. The pair gets the better of the two partners' tiers, so Patron on either
/// side is the long window for both.
const kOurRoomFreeKeepHours = 36;
const kOurRoomPatronKeepHours = 168;

/// The sentence that goes on the share dialog and the end-of-session screen.
String ourRoomKeepNote({required bool patron}) => patron
    ? 'It stays for 7 days after your session, so you can finish it at your own pace.'
    : 'It stays for $kOurRoomFreeKeepHours hours after your session, so you can continue tomorrow.';

/// The Patron offer shown to a free pair whose film is being kept: only when it is
/// true and useful, never during a film.
const ourRoomKeepUpsellLabel = 'Keep it for 7 days with Patron';

/// What the screen says when a retained film was released and this device has no copy.
String ourRoomCopyExpiredSubtitle({required bool patron}) {
  final kept = patron ? '7 days' : '$kOurRoomFreeKeepHours hours';
  return 'It was kept for $kept after your last session. Pick your own copy, or ask them to share it again.';
}
