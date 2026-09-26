import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/av/livekit_service.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/room_service.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/rewards/rewards_models.dart';

/// Mock user & session representing the local user.
final mockCurrentUser = User(
  id: 'user-alex',
  aud: 'authenticated',
  role: 'authenticated',
  email: 'alex@synctogether.app',
  emailConfirmedAt: '2026-01-01T00:00:00Z',
  appMetadata: const <String, dynamic>{},
  userMetadata: const <String, dynamic>{'full_name': 'Alex Rivers'},
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

final mockCurrentSession = Session(
  accessToken: 'mock-access-token',
  tokenType: 'bearer',
  user: mockCurrentUser,
);

const mockCurrentProfile = Profile(
  id: 'user-alex',
  displayName: 'Alex Rivers',
  isGuest: false,
  email: 'alex@synctogether.app',
);

final mockRoomOne = Room(
  id: 'demo-room-1',
  name: 'Cosmic Voyage Screening',
  code: 'X7K9P2',
  createdBy: 'user-alex',
  durationMinutes: 150,
  maxMembers: 8,
  avLevel: .video,
  mediaKind: .local,
  mediaName: 'Cosmic_Voyage_CC_4K.mp4',
  mediaDuration: const Duration(hours: 2, minutes: 49, seconds: 3),
  persistent: true,
  createdAt: DateTime.now().subtract(const Duration(minutes: 84)),
  expiresAt: DateTime.now().add(const Duration(minutes: 66)),
);

final mockRoomTwo = Room(
  id: 'demo-room-2',
  name: 'Open Source Animation Showcase',
  code: 'K4M8Y1',
  createdBy: 'user-alex',
  durationMinutes: 120,
  maxMembers: 8,
  avLevel: .video,
  mediaKind: .youtube,
  mediaName: 'Big Buck Bunny',
  mediaUrl: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
  mediaDuration: const Duration(minutes: 10, seconds: 34),
  persistent: true,
  createdAt: DateTime.now().subtract(const Duration(hours: 1)),
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

final mockRoomThree = Room(
  id: 'demo-room-3',
  name: 'Indie Short Film Night',
  code: 'N9P2L5',
  createdBy: 'user-alex',
  durationMinutes: 180,
  maxMembers: 8,
  avLevel: .voice,
  mediaKind: .youtube,
  mediaName: 'Tears of Steel',
  mediaUrl: 'https://www.youtube.com/watch?v=R6MlUcmOul8',
  mediaDuration: const Duration(minutes: 12, seconds: 14),
  persistent: true,
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  expiresAt: DateTime.now().add(const Duration(hours: 2)),
);

final mockMembersList = [
  RoomMember(
    roomId: 'demo-room-1',
    userId: 'user-alex',
    role: 'host',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 84)),
    profile: const Profile(id: 'user-alex', displayName: 'Alex Rivers', isGuest: false),
  ),
  RoomMember(
    roomId: 'demo-room-1',
    userId: 'user-sarah',
    role: 'member',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 75)),
    profile: const Profile(id: 'user-sarah', displayName: 'Sarah Chen', isGuest: false),
  ),
  RoomMember(
    roomId: 'demo-room-1',
    userId: 'user-david',
    role: 'member',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 60)),
    profile: const Profile(id: 'user-david', displayName: 'David Kim', isGuest: false),
  ),
  RoomMember(
    roomId: 'demo-room-1',
    userId: 'user-elena',
    role: 'guest',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 40)),
    profile: const Profile(id: 'user-elena', displayName: 'Elena Rostova', isGuest: true),
  ),
];

final mockPresentList = [
  PresentMember(
    userId: 'user-alex',
    displayName: 'Alex Rivers',
    role: 'host',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 84)),
    readyStatus: .ready,
    loadedFileName: 'Cosmic_Voyage_CC_4K.mp4',
  ),
  PresentMember(
    userId: 'user-sarah',
    displayName: 'Sarah Chen',
    role: 'member',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 75)),
    readyStatus: .ready,
    loadedFileName: 'Cosmic_Voyage_CC_4K.mp4',
  ),
  PresentMember(
    userId: 'user-david',
    displayName: 'David Kim',
    role: 'member',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 60)),
    readyStatus: .ready,
    loadedFileName: 'Cosmic_Voyage_CC_4K.mp4',
  ),
  PresentMember(
    userId: 'user-elena',
    displayName: 'Elena Rostova',
    role: 'guest',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 40)),
    readyStatus: .ready,
    loadedFileName: 'Cosmic_Voyage_CC_4K.mp4',
  ),
];

/// Keep every line **media-agnostic**. These are what the store screenshots
/// capture, and the footage behind them changes: a line naming what is on
/// screen ("this cosmic sequence") or pointing at a timestamp ("at 01:25:00")
/// goes stale the moment the demo plays something else, and reads as fake when
/// it contradicts the transport bar in the same frame. Praise the picture, the
/// sync or the company - never the plot.
final mockChatMessagesList = [
  ChatMessage(
    senderId: 'user-david',
    displayName: 'David Kim',
    content: 'Audio and video are locked in for everyone!',
    sentAt: DateTime.now().subtract(const Duration(minutes: 3)),
  ),
  ChatMessage(
    senderId: 'user-sarah',
    displayName: 'Sarah Chen',
    content: 'The color grading in this shot is unbelievable!',
    sentAt: DateTime.now().subtract(const Duration(minutes: 2)),
  ),
  ChatMessage(
    senderId: 'user-alex',
    displayName: 'Alex Rivers',
    content: 'Okay nobody scrub, this next bit is the best part.',
    sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
  ),
  ChatMessage(
    senderId: 'user-elena',
    displayName: 'Elena Rostova',
    content: 'Watching right from my laptop as a guest, zero lag at all!',
    sentAt: DateTime.now().subtract(const Duration(seconds: 25)),
  ),
];

class MockAuthService extends AuthService {
  bool _signedIn = true;
  final _authController = StreamController<AuthState>.broadcast();

  @override
  Session? get session => _signedIn ? mockCurrentSession : null;

  @override
  User? get user => _signedIn ? mockCurrentUser : null;

  @override
  bool get isSignedIn => _signedIn;

  @override
  bool get isGuest => false;

  @override
  Stream<AuthState> get onAuthStateChange => _authController.stream;

  @override
  Stream<String> get failures => const Stream.empty();

  @override
  void start() {}

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _authController.add(const AuthState(AuthChangeEvent.signedOut, null));
    ProfileService.instance.clear();
    EntitlementService.instance.clear();
    LiveKitService.isMockMode = false;
  }

  @override
  Future<void> deleteAccount() async {
    await signOut();
  }
}

class MockProfileService extends ProfileService {
  Profile _mockProfile = mockCurrentProfile;

  @override
  Profile? get profile => _mockProfile;

  @override
  Future<Profile?> load() async => _mockProfile;

  @override
  Future<void> updateDisplayName(String name) async {
    _mockProfile = _mockProfile.copyWith(displayName: name.trim());
    notifyListeners();
  }

  @override
  Future<void> uploadAvatar(Uint8List bytes) async {
    final jpeg = await compute(processAvatar, bytes);
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/demo_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(jpeg);
    _mockProfile = _mockProfile.copyWith(avatarUrl: file.path);
    notifyListeners();
  }

  @override
  void clear() {
    _mockProfile = mockCurrentProfile;
    notifyListeners();
  }
}

/// `--dart-define=DEMO_TIER=premium` runs demo mode as a Patron, so the
/// premium states (crowns, the Patron screen's "You're a Patron.", video
/// facecams) can be captured. Defaults to the free tier.
const kDemoTier = String.fromEnvironment('DEMO_TIER', defaultValue: kFreeTier);

class MockEntitlementService extends EntitlementService {
  static const _freeLimits = TierLimits(
    tier: kFreeTier,
    maxLiveRooms: 4,
    maxMembers: 8,
    maxSessionMinutes: 240,
    maxTotalSessionMinutes: 240,
    avLevel: .video,
    persistentRoomCap: 0,
    dormantHours: 24,
    freeExtensionMinutes: 0,
    mediaSharing: 'limited',
    mediaSharingWeeklyBytes: 2684354560,
  );

  static const _premiumLimits = TierLimits(
    tier: kPremiumTier,
    maxLiveRooms: 20,
    maxMembers: 16,
    maxSessionMinutes: 240,
    maxTotalSessionMinutes: 1440,
    avLevel: .video,
    persistentRoomCap: 20,
    dormantHours: 24,
    freeExtensionMinutes: 0,
    mediaSharing: 'full',
    mediaSharingWeeklyBytes: 0,
  );

  static const mockTierLimits = kDemoTier == kPremiumTier ? _premiumLimits : _freeLimits;

  @override
  TierLimits? get limits => mockTierLimits;

  @override
  TierLimits get limitsOrFallback => mockTierLimits;

  @override
  String get tier => mockTierLimits.tier;

  @override
  bool get isPremium => kDemoTier == kPremiumTier;

  /// A Paddle seat paid through a month from launch, so the Patron ticket
  /// carries a real-looking date in captures.
  @override
  PremiumTerm? get premiumTerm => kDemoTier == kPremiumTier
      ? PremiumTerm(until: DateTime.now().add(const Duration(days: 30)), source: 'paddle')
      : null;

  @override
  Future<TierLimits?> load() async => mockTierLimits;

  @override
  Future<TierLimits?> refresh() async => mockTierLimits;
}

class MockRoomService extends RoomService {
  late final List<MyRoom> _rooms = [
    MyRoom(
      room: mockRoomOne,
      state: .live,
      role: 'host',
      memberCount: 4,
      isOwner: true,
      isMember: true,
    ),
    MyRoom(
      room: mockRoomTwo,
      state: .live,
      role: 'host',
      memberCount: 3,
      isOwner: true,
      isMember: true,
    ),
    MyRoom(
      room: mockRoomThree,
      state: .live,
      role: 'host',
      memberCount: 6,
      isOwner: true,
      isMember: true,
    ),
  ];

  @override
  List<MyRoom> get myRooms => _rooms;

  @override
  bool get loadingMyRooms => false;

  @override
  Future<List<MyRoom>> loadMyRooms() async => _rooms;

  @override
  Future<Room?> fetchRoom(String roomId) async {
    final match = _rooms.where((r) => r.room.id == roomId).firstOrNull;
    return match?.room ?? mockRoomOne;
  }

  @override
  Future<List<RoomMember>> fetchMembers(String roomId) async => mockMembersList;

  @override
  Future<RoomMemberCosmetics> fetchMemberTiers(String roomId) async => const RoomMemberCosmetics(
    tiers: {'user-alex': 'free', 'user-sarah': 'free', 'user-david': 'free', 'user-elena': 'guest'},
    frames: {'user-alex': AvatarFrame.aurora, 'user-sarah': AvatarFrame.halo},
  );

  @override
  Future<void> syncServerTime() async {}

  @override
  DateTime get serverNow => DateTime.now();

  @override
  Future<Room> resumeRoom({required String roomId, required int minutes}) async {
    final r = await fetchRoom(roomId);
    return r!;
  }

  @override
  Future<Room> createRoom({
    required String name,
    required int durationMinutes,
    String? stagedId,
  }) async {
    final newRoom = Room(
      id: 'demo-room-${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Watch Party Room' : name.trim(),
      code: 'R${(10000 + (DateTime.now().millisecond % 90000)).toString()}',
      createdBy: 'user-alex',
      durationMinutes: durationMinutes,
      maxMembers: 8,
      avLevel: .video,
      mediaKind: .none,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(minutes: durationMinutes)),
    );
    _rooms.insert(
      0,
      MyRoom(
        room: newRoom,
        state: .live,
        role: 'host',
        memberCount: 1,
        isOwner: true,
        isMember: true,
      ),
    );
    notifyListeners();
    return newRoom;
  }

  @override
  Future<Room> joinRoom(String code, {RoomJoinSource via = RoomJoinSource.code}) async {
    final match = _rooms.where((r) => r.room.code.toUpperCase() == code.toUpperCase()).firstOrNull;
    return match?.room ?? mockRoomOne;
  }

  @override
  Future<Room> setRoomMedia({
    required String roomId,
    required RoomMediaKind kind,
    String? name,
    Duration? duration,
    String? url,
  }) async {
    final r = await fetchRoom(roomId);
    final updated = r!.copyWith(
      mediaKind: kind,
      mediaName: name,
      mediaDuration: duration,
      mediaUrl: url,
      mediaUpdatedAt: DateTime.now(),
    );
    final index = _rooms.indexWhere((m) => m.room.id == roomId);
    if (index != -1) {
      _rooms[index] = _rooms[index].copyWith(room: updated);
      notifyListeners();
    }
    return updated;
  }

  Room? _mockCurrentRoom;

  @override
  Room? get currentRoom => _mockCurrentRoom;

  @override
  Future<void> deleteRoom(String roomId) async {
    _rooms.removeWhere((r) => r.room.id == roomId);
    if (_mockCurrentRoom?.id == roomId) _mockCurrentRoom = null;
    notifyListeners();
  }

  @override
  Future<Room> endRoom(String roomId) async {
    final r = await fetchRoom(roomId);
    final updated = r!.copyWith(endedAt: DateTime.now());
    final index = _rooms.indexWhere((m) => m.room.id == roomId);
    if (index != -1) {
      _rooms[index] = _rooms[index].copyWith(room: updated, state: RoomState.expired);
      notifyListeners();
    }
    return updated;
  }

  @override
  Future<void> leaveRoom(String roomId) async {
    if (_mockCurrentRoom?.id == roomId) _mockCurrentRoom = null;
    notifyListeners();
  }

  @override
  Future<Room> setTransportLock({required String roomId, required bool locked}) async {
    final r = await fetchRoom(roomId);
    final updated = r!.copyWith(transportLock: locked);
    final index = _rooms.indexWhere((m) => m.room.id == roomId);
    if (index != -1) {
      _rooms[index] = _rooms[index].copyWith(room: updated);
      notifyListeners();
    }
    return updated;
  }

  @override
  Future<bool> updateMediaPosition({required String roomId, required Duration position}) async {
    return true;
  }

  @override
  Future<void> kickMember({
    required String roomId,
    required String userId,
    required bool allowRejoin,
  }) async {
    mockMembersList.removeWhere((m) => m.userId == userId);
  }
}

class MockSyncChannel implements SyncChannel {
  MockSyncChannel({required this.presence, required this.chatHistory});

  final List<PresentMember> presence;
  final List<ChatMessage> chatHistory;

  final handlers = <String, void Function(Map<String, dynamic>)>{};
  void Function()? presenceHandler;
  void Function(SyncSubscribeStatus, Object?)? subscribeCallback;

  @override
  SyncChannel onBroadcast({
    required String event,
    required void Function(Map<String, dynamic>) callback,
  }) {
    handlers[event] = callback;
    return this;
  }

  @override
  SyncChannel onPresenceSync(void Function() callback) {
    presenceHandler = callback;
    Future.microtask(callback);
    return this;
  }

  @override
  void subscribe(void Function(SyncSubscribeStatus, Object?) callback) {
    subscribeCallback = callback;
    Future.microtask(() => callback(SyncSubscribeStatus.subscribed, null));
  }

  @override
  Future<void> sendBroadcastMessage({
    required String event,
    required Map<String, dynamic> payload,
  }) async {
    handlers[event]?.call(payload);
  }

  @override
  Future<void> track(Map<String, dynamic> payload) async {}

  @override
  List<Map<String, dynamic>> presenceState() {
    return presence
        .map(
          (p) => {
            'user_id': p.userId,
            'display_name': p.displayName,
            'role': p.role,
            'joined_at': p.joinedAt.toIso8601String(),
            'ready_status': p.readyStatus.name,
            'loaded_file_name': p.loadedFileName,
          },
        )
        .toList();
  }

  @override
  Future<void> unsubscribe() async {}
}

class MockSyncBackend implements SyncBackend {
  MockSyncBackend({required this.room, required this.presence, required this.chatHistory});

  final Room room;
  final List<PresentMember> presence;
  final List<ChatMessage> chatHistory;

  @override
  SyncChannel channel(String topic) {
    return MockSyncChannel(presence: presence, chatHistory: chatHistory);
  }

  @override
  Future<MembershipRow?> loadMembership(String roomId, String userId) async {
    return MembershipRow(
      role: 'host',
      joinedAt: DateTime.now().subtract(const Duration(minutes: 84)),
    );
  }

  @override
  Future<Room?> fetchRoom(String roomId) async => RoomService.instance.fetchRoom(roomId);

  @override
  Future<List<ChatMessage>> loadChatHistory(String roomId) async => chatHistory;

  @override
  Future<void> insertChatMessage({
    required String roomId,
    required String senderId,
    required String content,
  }) async {
    chatHistory.add(
      ChatMessage(
        senderId: senderId,
        displayName: 'Alex Rivers',
        content: content,
        sentAt: DateTime.now(),
      ),
    );
  }
}

/// Installs mock dependency overrides across all services.
void installMockDependencies() {
  AuthService.instance = MockAuthService();
  ProfileService.instance = MockProfileService();
  EntitlementService.instance = MockEntitlementService();
  RoomService.instance = MockRoomService();
  SyncService.defaultBackendOverride = MockSyncBackend(
    room: mockRoomOne,
    presence: mockPresentList,
    chatHistory: mockChatMessagesList,
  );
  LiveKitService.isConfiguredOverride = true;
  LiveKitService.isMockMode = true;
}
