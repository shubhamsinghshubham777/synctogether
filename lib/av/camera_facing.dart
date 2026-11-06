/// Whether a self-view should be mirrored. Mirroring is a selfie convention: it
/// makes the preview behave like a mirror for a camera that faces the person
/// holding the device, and is wrong for a camera that faces the room (text and
/// scenes come out reversed).
///
/// Order of trust: the track's own `facingMode` setting (reported as `user` /
/// `environment` by WebRTC on iOS and Android), then the device label (`Back
/// Camera`, `Rear Camera`, ... on iOS; `camera2 0, facing back` on Android),
/// then default to mirrored - desktop webcams are front-facing and report neither.
bool shouldMirrorCamera({String? facingMode, String? label}) {
  switch (facingMode) {
    case 'user' || 'front':
      return true;
    case 'environment' || 'back' || 'rear':
      return false;
  }
  final l = (label ?? '').toLowerCase();
  if (l.contains('back') || l.contains('rear') || l.contains('environment')) return false;
  return true;
}
