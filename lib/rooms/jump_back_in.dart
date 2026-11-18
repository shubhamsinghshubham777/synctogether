import 'room_models.dart';

/// How many people other than you are in [room], by membership.
///
/// Presence lives in Realtime, not in the database, so the lobby cannot ask
/// "who is in there right now" without joining the room's channel. Membership is
/// the nearest honest answer: leaving deletes your row, so a member who is still
/// listed is someone who has not left (an open session, or a closed app).
int othersIn(MyRoom room) => (room.memberCount - (room.isMember ? 1 : 0)).clamp(0, 1 << 20);

/// The rooms worth a "Jump back in" strip: live, with somebody else in them, and
/// not the one you are in or have just left (a leave waits out its Undo window,
/// during which the room still lists you as a member).
///
/// Newest first, because the newest is the one you most likely stepped out of.
List<MyRoom> jumpBackInRooms(
  List<MyRoom> rooms, {
  String? insideRoomId,
  Set<String> leavingRoomIds = const {},
}) {
  final out = [
    for (final r in rooms)
      if (r.isLive &&
          !r.room.isOurRoom &&
          r.room.id != insideRoomId &&
          !leavingRoomIds.contains(r.room.id) &&
          othersIn(r) >= 1)
        r,
  ];
  out.sort((a, b) => b.room.createdAt.compareTo(a.room.createdAt));
  return out;
}

/// Minutes left when a timed session is about to end, else null. The last few
/// minutes are worth saying: the rejoin is then a choice made with the clock in view.
int? endingSoonMinutes(MyRoom room, DateTime serverNow, {int within = 5}) {
  if (room.room.persistent) return null;
  final left = room.room.expiresAt.difference(serverNow);
  if (left.isNegative || left > Duration(minutes: within)) return null;
  return left.inMinutes.clamp(1, within);
}
