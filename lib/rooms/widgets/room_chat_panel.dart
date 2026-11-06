import 'dart:async';
import '../../ui/booth_icons.g.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/player/youtube/youtube_links.dart';
import 'package:synctogether/rooms/emoji/emoji_logic.dart';
import 'package:synctogether/rooms/emoji/emoji_prefs.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/keyboard_dismiss.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';
import 'package:synctogether/ui/reveal.dart';

import '../../rewards/rewards_models.dart';
import 'emoji_picker.dart';
import 'emoji_quick_bar.dart';
import '../roster_fold.dart';
import 'room_roster.dart';

export 'room_roster.dart' show ChatRosterSeat;

/// Pointer hover-intent before the picker opens: long enough that sweeping the
/// mouse across the button on the way to the field does not pop it.
/// The composer's line height, in font sizes. Hanken Grotesk's own metrics
/// (ascent 1.0, descent 0.303) already sum to ~1.3, so with even leading the
/// cap-height midline lands on the line's centre.
const _kFieldLineHeight = 1.3;

const kEmojiHoverOpenDelay = Duration(milliseconds: 250);

/// Grace after the pointer leaves both the button and the picker, so a
/// diagonal move from one to the other does not close it.
const kEmojiHoverCloseDelay = Duration(milliseconds: 300);

/// The counter appears only once a message nears the limit.
const _kCounterFrom = 450;

/// The send button's diameter, and the gap between it and the field.
const _kSendExtent = 42.0;
const _kComposerGap = 10.0;

/// The soft keyboard's tallest height in the current orientation - what the
/// inline emoji picker takes over. Not the latest reading, which shrinks as the
/// keyboard slides away, exactly when the picker is sized from it. Shared by the
/// room (which reserves the picker's strip) and the chat panel (which draws it),
/// so both agree to the pixel.
class SoftKeyboardMemory {
  double _tallest = 0;
  double _bottomSafe = 0;
  double _live = 0;
  bool _landscape = false;

  /// 0..1, how much of its strip the inline picker has unfolded when there is
  /// no keyboard to trade places with (see [pickerShown]). 1 whenever it is
  /// handed the keyboard's strip or not on screen. Written by the chat panel's
  /// animation; the room reads it to give up the same height to the picture
  /// progressively, so the two always agree to the pixel.
  final pickerReveal = ValueNotifier<double>(1);

  /// The keyboard's height at the last [observe].
  double get live => _live;

  /// What the picker is worth when no keyboard has ever shown.
  static const double fallback = 280;

  /// Reads [view]'s live keyboard height (logical px), remembering the tallest.
  double observe(ui.FlutterView view) {
    final landscape = view.physicalSize.width > view.physicalSize.height;
    if (landscape != _landscape) {
      _landscape = landscape;
      _tallest = 0;
    }
    final live = view.viewInsets.bottom / view.devicePixelRatio;
    _live = live;
    if (live > _tallest) _tallest = live;
    _bottomSafe = view.viewPadding.bottom / view.devicePixelRatio;
    return live;
  }

  /// Whether a soft keyboard has ever shown: with none (a hardware keyboard),
  /// there is nothing for the picker to trade places with.
  bool get hasKeyboard => _tallest > 0;

  /// The full strip the picker and the keyboard trade between them.
  double get pickerStrip => _tallest > 0 ? _tallest : fallback;

  /// The picker's own height once the keyboard is gone: the strip less the
  /// bottom inset a `SafeArea` above already keeps clear.
  double get pickerBody => math.max(0.0, pickerStrip - _bottomSafe);

  /// How much of that strip the picker holds while the keyboard is [live] tall:
  /// the two always add up to one strip, so nothing above moves in the swap.
  /// The home indicator / nav bar counts as occupied once the keyboard is
  /// gone: it is inside the keyboard's height while that is up, and a
  /// `SafeArea` above takes it back when it leaves.
  double pickerShown(double live) => math.max(0.0, pickerStrip - math.max(live, _bottomSafe));

  /// [pickerShown] as currently unfolded: the strip the picker holds right now.
  double pickerHeld(double live) => pickerShown(live) * pickerReveal.value;
}

class RoomChatPanel extends StatefulWidget {
  const RoomChatPanel({
    super.key,
    required this.sync,
    required this.messages,
    required this.typingNames,
    required this.watchingCount,
    required this.onClose,
    required this.onSend,
    required this.onCopied,
    this.onPlaySharedVideo,
    this.onReportMessage,
    this.embedded = false,
    this.docked = false,
    this.closable = true,
    this.roster,
    this.rosterFold,
    this.premiumMembers = const {},
    this.memberFrames = const {},
    this.draftController,
    this.onInlinePickerChanged,
    this.keyboardMemory,
  });

  final SyncService sync;
  final List<ChatMessage> messages;
  final List<String> typingNames;
  final int watchingCount;
  final VoidCallback onClose;
  final ValueChanged<String> onSend;
  final VoidCallback onCopied;
  final void Function(String videoId, String sharedBy)? onPlaySharedVideo;
  final ValueChanged<ChatMessage>? onReportMessage;
  final Set<String> premiumMembers;
  final Map<String, AvatarFrame> memberFrames;

  /// The half-typed message, owned by the room so it survives the panel
  /// remounting when a layout change (fullscreen, Split View, a resize across
  /// the theatre breakpoint) rebuilds the tree around it. Null: the panel owns
  /// its own and the draft dies with it.
  final TextEditingController? draftController;

  /// Told when the touch emoji picker takes over (or hands back) the soft
  /// keyboard's place, so the room can treat it exactly like a keyboard that is
  /// up - the header stays collapsed through the hand-off instead of popping
  /// back for the frames in between.
  final ValueChanged<bool>? onInlinePickerChanged;

  /// Shared with the room when it reserves the picker's strip; the panel keeps
  /// its own otherwise.
  final SoftKeyboardMemory? keyboardMemory;

  /// Embedded (mobile portrait) skips its own panel shell + close button.
  final bool embedded;

  /// Docked into the theatre layout's right column: a flat Seat column with a
  /// Rail edge instead of a floating panel. Keeps its close button.
  final bool docked;

  /// False where the room's own chat key already closes the panel (the
  /// desktop compositions), so the boards' panels carry no second close.
  final bool closable;

  /// Who is in the room, drawn as the header in place of "Party chat" - each
  /// seat's ring turns Cue as they clear the gate. Null keeps the plain header.
  final List<ChatRosterSeat>? roster;

  /// Embedded only: lets the viewer fold the roster to a slim row. Null (every
  /// docked and floating chat) keeps the plain header - the desktop column has
  /// the height to spare and the fold is about a phone's.
  final RosterFold? rosterFold;

  @override
  State<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends State<RoomChatPanel> with SingleTickerProviderStateMixin {
  late final _controller = widget.draftController ?? TextEditingController();
  late final _ownsController = widget.draftController == null;
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  Timer? _typingDebounce;
  bool _sentTyping = false;

  // Emoji picker. Pointer: a popover above the composer, opened by hover
  // intent (and then transient) or by a click (then [_pickerPinned] until
  // Esc, an outside click, the button or a send). Touch: inline beneath the
  // composer in place of the soft keyboard.
  final _emoji = EmojiPrefs.instance;
  final _pickerPortal = OverlayPortalController();
  final _tapGroup = Object();
  bool _pickerOpen = false;
  bool _pickerPinned = false;
  bool _pickerIconHovered = false;
  Timer? _hoverOpen;
  Timer? _hoverClose;
  late final _kbMemory = widget.keyboardMemory ?? SoftKeyboardMemory();

  /// Touch: the picker stays mounted while the keyboard rises back over it, so
  /// the two trade the same strip of screen instead of the picker vanishing
  /// first and the composer dropping for the frames before the keyboard lands.
  bool _pickerLinger = false;
  Timer? _lingerTimer;

  /// Touch, no keyboard to trade with: the picker folds its strip in and out
  /// over [PTMotion.panel] instead of appearing whole. 1 = fully unfolded. The
  /// curved value is published on [SoftKeyboardMemory.pickerReveal]; a hand-off
  /// from/to a keyboard pins it at 1 (the keyboard's own slide is the motion).
  late final _reveal = AnimationController(vsync: this, value: 1)
    ..addListener(_publishReveal)
    ..addStatusListener(_onRevealStatus);

  /// The picker is folding away with nothing taking its strip: still mounted
  /// (and still reserved by the room) until the fold ends.
  bool _pickerClosing = false;
  int _limitShake = 0;

  /// Snapshot, not a live read: refreshed when the panel mounts (it remounts
  /// on every open) and after a send - never while the pointer is on it.
  late List<QuickSlot> _quickSlots = _emoji.quickSlots();

  // What the list was last laid out with. Snapshotted here rather than diffed
  // against `oldWidget`, because the room owns one mutable list and appends to
  // it in place - `widget.messages` and `oldWidget.messages` are the same object.
  int _seenCount = 0;
  DateTime? _seenLast;
  bool _seenTyping = false;

  /// Messages whose entrance has already played. Required, not an optimisation:
  /// `itemBuilder` re-runs every time a row scrolls back into view, so a
  /// one-shot animation keyed only by message identity would replay on every
  /// scroll. Keyed by *value* rather than object identity so the reconnect
  /// history merge - which swaps equivalent rows in place - doesn't re-animate
  /// the entire backlog.
  final _animated = <String>{};

  static String _keyOf(ChatMessage m) =>
      '${m.senderId}|${m.sentAt.microsecondsSinceEpoch}|${m.content}';

  @override
  void initState() {
    super.initState();
    _snapshot();
    _observeRoster();
    // Everything already loaded is history: it renders statically, only
    // messages appended after mount animate in.
    _animated.addAll(widget.messages.map(_keyOf));
    // The panel mounts with history already loaded (and remounts every time it
    // is reopened), so land on the newest message instead of the top.
    _scrollToBottom(animate: false);
    if (!_emoji.loaded) {
      _emoji.load().then((_) {
        if (mounted) setState(() => _quickSlots = _emoji.quickSlots());
      });
    }
  }

  @override
  void didUpdateWidget(covariant RoomChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _observeRoster();
    // Count alone misses a history reload that swaps rows in place, and the
    // typing row counts towards the list's extent too.
    final last = widget.messages.lastOrNull;
    if (widget.messages.length == _seenCount &&
        last?.sentAt == _seenLast &&
        widget.typingNames.isNotEmpty == _seenTyping) {
      return;
    }
    // Read the offset *before* the new row lays out - someone who scrolled up to
    // read history keeps their place; our own outgoing message always wins.
    final follow = _nearBottom || last?.senderId == widget.sync.userId;
    _snapshot();
    if (follow) _scrollToBottom();
  }

  /// Tells the roster fold how many are in and how many have cleared the gate,
  /// so it can fold itself once everyone has.
  void _observeRoster() {
    final seats = widget.roster;
    if (seats == null) return;
    widget.rosterFold?.observe(total: seats.length, ready: seats.where((s) => s.ready).length);
  }

  void _snapshot() {
    _seenCount = widget.messages.length;
    _seenLast = widget.messages.lastOrNull?.sentAt;
    _seenTyping = widget.typingNames.isNotEmpty;
  }

  /// Within a bubble or so of the end. True before the list has been laid out
  /// (nothing to scroll yet) so the first messages of a room still stick.
  bool get _nearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= 80;
  }

  /// Runs after the frame that lays the new row out - `maxScrollExtent` is only
  /// correct once the list has measured it.
  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(target, duration: Durations.short4, curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reveal.duration = PTMotion.functional(context, PTMotion.panel);
  }

  void _publishReveal() {
    _kbMemory.pickerReveal.value = PTMotion.emphasized.transform(_reveal.value);
  }

  void _onRevealStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _pickerClosing) _finishClose();
  }

  /// The fold is over: nothing holds the strip any more.
  void _finishClose() {
    if (!_pickerClosing) return;
    EmptyTapHook.release(_closePickerFromEmptyTap);
    if (mounted) setState(() => _pickerClosing = false);
    widget.onInlinePickerChanged?.call(false);
  }

  /// With no keyboard to hand the strip to (or from), fold it instead of
  /// popping; with one up, or nothing unfolded, simply end.
  void _endInline() {
    if (_reveal.value > 0 && _kbMemory.live < 0.5) {
      if (mounted) setState(() => _pickerClosing = true);
      _reveal.reverse();
    } else {
      EmptyTapHook.release(_closePickerFromEmptyTap);
      widget.onInlinePickerChanged?.call(false);
    }
  }

  // Touch: the list sits inside a [SelectionArea], whose own tap recogniser
  // (it clears the selection) is deeper than, and so beats, the root's
  // [TapToDismissKeyboard] in the gesture arena over the whole list - gaps and
  // background included. So a tap there never reaches [EmptyTapHook]. A raw
  // pointer [Listener] takes no part in the arena: it sees the tap whoever
  // wins it, and a bubble marks its own pointer-down ([_ownTap]) so a tap on a
  // message is left to selection.
  Offset? _tapDown;
  Duration? _tapDownAt;
  bool _tapOnBubble = false;

  Widget _ownTap(Widget child) => Listener(onPointerDown: (_) => _tapOnBubble = true, child: child);

  Widget _emptyTapCatcher(Widget child) {
    if (!_touch) return child;
    return Listener(
      onPointerDown: (e) {
        // Bubbles (deeper) have already run; a second finger voids the tap.
        _tapDown = _tapDown == null && !_tapOnBubble ? e.position : null;
        _tapDownAt = e.timeStamp;
      },
      onPointerUp: (e) {
        final down = _tapDown;
        final quick = _tapDownAt != null && e.timeStamp - _tapDownAt! < kLongPressTimeout;
        _tapDown = null;
        _tapOnBubble = false;
        if (down != null && quick && (e.position - down).distance < kTouchSlop) {
          _closePickerFromEmptyTap();
        }
      },
      onPointerCancel: (_) {
        _tapDown = null;
        _tapOnBubble = false;
      },
      child: child,
    );
  }

  /// A tap no one claimed: the same rule that closes the keyboard closes the
  /// picker, folding it, with the keyboard staying down.
  void _closePickerFromEmptyTap() {
    if (_pickerOpen && _touch) _closePicker();
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _hoverOpen?.cancel();
    _hoverClose?.cancel();
    _lingerTimer?.cancel();
    // The room treats the picker as a keyboard; whatever unmounts the panel
    // must not leave it believing one is still up.
    if (_pickerOpen || _pickerLinger || _pickerClosing) {
      final told = widget.onInlinePickerChanged;
      WidgetsBinding.instance.addPostFrameCallback((_) => told?.call(false));
    }
    EmptyTapHook.release(_closePickerFromEmptyTap);
    _reveal.dispose();
    if (_ownsController) _controller.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    if (text.isNotEmpty && !_sentTyping) {
      _sentTyping = true;
      widget.sync.broadcastTyping(true);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _sentTyping = false;
      widget.sync.broadcastTyping(false);
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _typingDebounce?.cancel();
    if (_sentTyping) {
      _sentTyping = false;
      widget.sync.broadcastTyping(false);
    }
    _emoji.noteSent(text);
    // The field keeps focus (below), so the keyboard rises into the strip.
    _closePicker(keyboardFollows: _touch);
    setState(() => _quickSlots = _emoji.quickSlots());
    widget.onSend(text);
    // Keep the caret in the field for the next line - Enter would otherwise hand
    // focus back to the player shortcuts (so the next Space toggles playback),
    // and tapping the send button never had it to begin with.
    _inputFocus.requestFocus();
  }

  bool get _touch => inputOf(context) == PTInput.touch;

  void _openPicker({required bool pinned}) {
    _hoverOpen?.cancel();
    _hoverClose?.cancel();
    if (_touch) {
      // The picker takes the keyboard's place rather than stacking on it: it
      // grows exactly as the keyboard leaves (see [_inlinePickerShown]).
      _lingerTimer?.cancel();
      // A keyboard up trades its strip with the picker (no motion of ours);
      // with none, the strip folds open. Reopening mid-fold carries on from
      // where it is.
      final onScreen = _pickerClosing || _pickerLinger || _pickerOpen;
      if (_kbMemory.live > 0.5) {
        _reveal.value = 1;
      } else {
        if (!onScreen) _reveal.value = 0;
        _reveal.forward();
      }
      _inputFocus.unfocus();
      EmptyTapHook.claim(_closePickerFromEmptyTap);
    } else {
      _pickerPortal.show();
    }
    setState(() {
      _pickerOpen = true;
      _pickerLinger = false;
      _pickerClosing = false;
      _pickerPinned = pinned;
    });
    if (_touch) widget.onInlinePickerChanged?.call(true);
  }

  /// [keyboardFollows]: touch, and the field is about to take focus back, so
  /// the picker lingers while the keyboard rises into its place.
  void _closePicker({bool keyboardFollows = false}) {
    _hoverOpen?.cancel();
    _hoverClose?.cancel();
    if (!_pickerOpen) return;
    _pickerPortal.hide();
    final linger = _touch && keyboardFollows && _kbMemory.hasKeyboard;
    setState(() {
      _pickerOpen = false;
      _pickerPinned = false;
      _pickerLinger = linger;
    });
    if (linger) {
      _lingerTimer?.cancel();
      // The keyboard normally lands well inside this; the timer is for a
      // device that never raises one (a hardware keyboard on a tablet).
      _lingerTimer = Timer(PTMotion.panel + PTMotion.hover, _endLinger);
    } else if (_touch) {
      _endInline();
    }
  }

  void _endLinger() {
    _lingerTimer?.cancel();
    if (!mounted || !_pickerLinger) return;
    setState(() => _pickerLinger = false);
    // The keyboard never came (or has landed over the picker).
    _endInline();
  }

  void _togglePicker() {
    if (_pickerOpen && (_pickerPinned || _touch)) {
      // Touch: hand the keyboard back, which is why they closed it.
      _closePicker(keyboardFollows: true);
      _inputFocus.requestFocus();
    } else {
      _openPicker(pinned: true);
      if (!_touch) _inputFocus.requestFocus();
    }
  }

  void _hoverEnter() {
    _hoverClose?.cancel();
    if (_pickerOpen) return;
    // Build and lay the picker out offstage now, inside the intent delay, so
    // the frame that reveals it only has to paint - building ~70 glyph cells
    // on the same frame as the entrance is what made it stutter.
    _pickerPortal.show();
    _hoverOpen = Timer(kEmojiHoverOpenDelay, () {
      if (mounted) _openPicker(pinned: false);
    });
  }

  void _hoverExit() {
    _hoverOpen?.cancel();
    // Swept past without opening: drop the warmed, still-offstage picker.
    if (!_pickerOpen) {
      _pickerPortal.hide();
      return;
    }
    if (_pickerPinned) return;
    _hoverClose = Timer(kEmojiHoverCloseDelay, () {
      if (mounted && !_pickerPinned) _closePicker();
    });
  }

  void _insert(String emoji) {
    final value = _controller.value;
    final next = insertEmoji(
      value.text,
      value.selection.start,
      value.selection.end,
      emoji,
      maxCodepoints: kChatMaxCodepoints,
    );
    if (next == null) {
      setState(() => _limitShake++);
      return;
    }
    _controller.value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.caret),
    );
    _onTextChanged(next.text);
    // Pointer keeps typing where it was; touch leaves the keyboard down so it
    // does not rise over the picker.
    if (!_touch) _inputFocus.requestFocus();
  }

  Future<void> _customize(int slot) async {
    _closePicker();
    await showQuickBarEditor(context, initialSlot: slot, prefs: _emoji);
    if (mounted) setState(() => _quickSlots = _emoji.quickSlots());
  }

  /// Esc closes the picker before anything else - the field keeps focus, since
  /// whoever pressed it is still composing - and Ctrl/Cmd+E toggles it.
  KeyEventResult _onComposerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && _pickerOpen) {
      _closePicker();
      _inputFocus.requestFocus();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.keyE && (keyboard.isMetaPressed || keyboard.isControlPressed)) {
      _togglePicker();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // A landscape phone with the keyboard up leaves the panel little more than
    // the composer's height. The composer is what the user is there for, so the
    // header gives way first rather than pushing the field off the bottom.
    final content = LayoutBuilder(
      builder: (context, constraints) {
        // The panel resizes as the keyboard rises, so this builder sees it.
        // Read from the View: the Scaffold strips insets from what we inherit.
        final view = View.of(context);
        final keyboard = _kbMemory.observe(view);
        // The keyboard is back over the picker: it has nothing left to hold.
        if (_pickerLinger && keyboard >= _kbMemory.pickerStrip - 0.5) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _endLinger());
        }
        final inline = _touch && (_pickerOpen || _pickerLinger || _pickerClosing);
        // Phone portrait: while a keyboard or the picker holds the lower half,
        // the roster strip is the first thing to go, so one chat bubble and the
        // composer always fit. Decided on the inset, not on the panel's height
        // (which changes every frame of the slide and would flicker it).
        final inputUp = widget.embedded && (keyboard > 0 || inline);
        // What the list and composer have, with the picker's changing slice
        // taken out. The panel grows by exactly what the picker takes while the
        // keyboard leaves, so judging "does the quick bar fit" on the raw
        // height would flip it mid-swap and shift the composer by its height.
        final avail = inline
            ? constraints.maxHeight - _kbMemory.pickerShown(keyboard)
            : constraints.maxHeight;
        return _content(
          // An inline picker needs the room more than the header does.
          showHeader: !inputUp && constraints.maxHeight >= (inline ? 480 : 240),
          denseList: inputUp || (widget.embedded && avail < 300),
          pickerHeight: inline ? _kbMemory.pickerBody : null,
          keyboard: keyboard,
          tight: avail < 200,
          // The field and header grow with the text scale; the bar does not,
          // so the room it needs before appearing grows with them.
          quickBar: avail >= 300 + 90 * (MediaQuery.textScalerOf(context).scale(1) - 1),
        );
      },
    );

    if (widget.embedded) return content;
    if (widget.docked) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: PTColors.glassBase,
          border: Border(left: BorderSide(color: PTColors.aisle)),
        ),
        child: content,
      );
    }
    return GlassPanel(radius: PTRadius.panel, baseColor: PTColors.surfaceBase, child: content);
  }

  Widget _content({
    required bool showHeader,
    required bool denseList,
    required double? pickerHeight,
    required double keyboard,
    required bool tight,
    required bool quickBar,
  }) {
    return Column(
      children: [
        // Folds away (and back) rather than popping when a keyboard or the
        // inline picker takes the lower half: the list and composer follow the
        // eased height instead of jumping by the whole strip.
        PTReveal(
          visible: showHeader,
          child: widget.roster != null ? _rosterHeader(widget.roster!) : _plainHeader(),
        ),
        // One pass lays the composer out at its natural height, gives the
        // inline picker what is left of what it wants, and the list the rest -
        // exact on the first frame, which measuring a GlobalKey never is.
        Expanded(
          child: CustomMultiChildLayout(
            // The picker is whatever the keyboard has left of its strip: the
            // two always add up to one keyboard's height, so nothing above
            // moves while they trade places.
            delegate: _ComposerLayout(
              picker: pickerHeight == null ? null : _kbMemory.pickerShown(keyboard),
              body: pickerHeight ?? 0,
              reveal: _kbMemory.pickerReveal,
            ),
            children: [
              LayoutId(
                id: _ComposerSlot.list,
                child: _emptyTapCatcher(
                  SelectionArea(
                    child: ListView.separated(
                      controller: _scrollController,
                      keyboardDismissBehavior: .onDrag,
                      physics: const ChatScrollPhysics(),
                      padding: _spare
                          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
                          : denseList
                          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                          : const EdgeInsets.all(20),
                      // The typing slot is always present so it can collapse rather than
                      // pop; its own gap lives inside it, which is why the separator
                      // before it is suppressed.
                      itemCount: widget.messages.length + 1,
                      separatorBuilder: (_, index) => index == widget.messages.length - 1
                          ? const SizedBox.shrink()
                          : SizedBox(height: _spare || denseList ? 10 : 14),
                      itemBuilder: (context, index) {
                        if (index == widget.messages.length) {
                          return _typingRow();
                        }
                        final message = widget.messages[index];
                        final bubble = _ownTap(
                          _MessageRow(
                            message: message,
                            own: message.senderId == widget.sync.userId,
                            premium: widget.premiumMembers.contains(message.senderId),
                            frame: widget.memberFrames[message.senderId],
                            onCopied: widget.onCopied,
                            onPlaySharedVideo: widget.onPlaySharedVideo,
                            onReport: widget.onReportMessage,
                            spare: _spare,
                          ),
                        );
                        final key = _keyOf(message);
                        if (!_animated.add(key)) return bubble;
                        return PTEntrance(duration: PTMotion.state, offset: 6, child: bubble);
                      },
                    ),
                  ),
                ),
              ),
              // Tighter still (landscape keyboard at large text), the composer caps
              // its own scale so the field and its send button both fit.
              LayoutId(
                id: _ComposerSlot.composer,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: tight ? 1.3 : double.infinity,
                  child: _composer(tight: tight, quickBar: quickBar),
                ),
              ),
              if (pickerHeight != null)
                LayoutId(
                  id: _ComposerSlot.picker,
                  child: _inlinePicker(_kbMemory.pickerShown(keyboard), _kbMemory.pickerReveal),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The Room at minimum window board: "Chat" and a mono head count on one
  /// Aisle-ruled line.
  Widget _plainHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 12, widget.closable && !widget.embedded ? 8 : 14, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PTColors.aisle)),
      ),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Text(
              'Chat',
              maxLines: 1,
              overflow: .ellipsis,
              style: PTText.buttonLabel.copyWith(fontSize: 14),
            ),
          ),
          Text(
            '${widget.watchingCount} IN',
            maxLines: 1,
            style: PTText.label.copyWith(fontSize: 10, color: PTColors.fgMute),
          ),
          if (widget.closable && !widget.embedded)
            PTIconButton(
              icon: BoothIcons.close,
              glass: false,
              size: 30,
              iconSize: 18,
              color: PTColors.fgDim,
              tooltip: 'Close chat (C)',
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  /// "IN THE ROOM · 4" over a row of seats. One line that scrolls sideways
  /// rather than wrapping: a sixteen-seat room must not eat the chat's height.
  Widget _rosterHeader(List<ChatRosterSeat> seats) {
    final fold = widget.rosterFold;
    if (widget.embedded && fold != null) return FoldableRoster(seats: seats, fold: fold);
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, widget.closable && !widget.embedded ? 12 : 20, 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PTColors.aisle)),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'IN THE ROOM · ${seats.length}',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: PTText.label.copyWith(letterSpacing: 11 * 0.14, color: PTColors.fgMute),
                ),
              ),
              if (widget.closable && !widget.embedded)
                PTIconButton(
                  icon: BoothIcons.close,
                  glass: false,
                  size: 30,
                  iconSize: 18,
                  color: PTColors.white(0.6),
                  tooltip: 'Close chat (C)',
                  onPressed: widget.onClose,
                ),
            ],
          ),
          RosterRings(seats: seats),
        ],
      ),
    );
  }

  /// The floating desktop panel (Room at minimum window board) is the
  /// sparest: no quick bar and no send key - Enter sends - and a 38 px field.
  bool get _spare => !widget.docked && !widget.embedded && !_touch;

  Widget _composer({required bool tight, required bool quickBar}) {
    final length = _controller.text.runes.length;
    final spare = _spare;
    quickBar = quickBar && !spare;
    final composer = Container(
      padding: tight
          ? const EdgeInsets.fromLTRB(14, 8, 14, 8)
          : spare
          ? const EdgeInsets.fromLTRB(12, 10, 12, 10)
          : widget.docked
          ? const EdgeInsets.fromLTRB(20, 10, 20, 16)
          : const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: PTColors.aisle)),
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          // The composer is what a short panel is there for, so the bar gives
          // way first; the picker button still reaches everything.
          // The full composer width, send column included, as every board
          // draws it.
          // Flexible: while it folds away the composer may already be short
          // of room for it, and it must give way rather than overflow.
          Flexible(
            child: PTReveal(
              visible: quickBar,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: EmojiQuickBar(slots: _quickSlots, onPick: _insert, onCustomize: _customize),
              ),
            ),
          ),
          Row(
            // The send button stays on the last line as the composer grows.
            crossAxisAlignment: .end,
            spacing: _kComposerGap,
            children: [
              Expanded(
                child: PTShake(
                  trigger: _limitShake,
                  child: Container(
                    decoration: BoxDecoration(
                      color: PTColors.canvas,
                      border: Border.all(color: PTColors.rail),
                      borderRadius: BorderRadius.circular(PTRadius.control),
                    ),
                    // One row, centred: the icon and the field share a centre
                    // line by construction, with no padding matched between
                    // them. At one line the box is the send button's height
                    // (inside its border); as the field grows, the icon stays
                    // mid-height.
                    constraints: BoxConstraints(minHeight: spare ? 38 : _kSendExtent),
                    child: Row(
                      children: [
                        _pickerIcon(),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: _field(tight: tight),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!spare) _sendButton(),
            ],
          ),
          if (length >= _kCounterFrom) Align(alignment: .centerRight, child: _counter(length)),
        ],
      ),
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onComposerKey,
      child: TapRegion(
        groupId: _tapGroup,
        child: OverlayPortal.overlayChildLayoutBuilder(
          controller: _pickerPortal,
          overlayChildBuilder: _popover,
          child: composer,
        ),
      ),
    );
  }

  Widget _counter(int length) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Text(
      '$length/$kChatMaxCodepoints',
      style: PTText.finePrint.copyWith(
        fontSize: 11,
        color: length >= kChatMaxCodepoints ? PTColors.warning : PTColors.white(0.45),
      ),
    ),
  );

  /// A bare glyph, not a button: dim at rest, full on hover or while the
  /// picker is pinned open. Hover intent still opens the popover on pointer.
  Widget _pickerIcon() {
    final chord = defaultTargetPlatform == TargetPlatform.macOS ? '⌘E' : 'Ctrl+E';
    final lit = _pickerIconHovered || (_pickerOpen && (_pickerPinned || _touch));
    return Tooltip(
      message: _pickerOpen ? 'Close emoji ($chord)' : 'Emoji ($chord)',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _pickerIconHovered = true);
          if (!_touch) _hoverEnter();
        },
        onExit: (_) {
          setState(() => _pickerIconHovered = false);
          if (!_touch) _hoverExit();
        },
        child: Semantics(
          button: true,
          label: 'Emoji',
          child: GestureDetector(
            behavior: .opaque,
            onTap: _togglePicker,
            child: Padding(
              // Touch keeps a finger-sized target; the glyph is still 20.
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: _touch ? 12 : 4),
              child: AnimatedOpacity(
                opacity: lit ? 1 : 0.55,
                duration: PTMotion.functional(context, PTMotion.hover),
                curve: PTMotion.enter,
                child: const Icon(BoothIcons.mood, size: 20, color: PTColors.fg),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double get _fieldFontSize => _spare ? 13 : 15;
  TextStyle get _fieldStyle => PTText.body.copyWith(fontSize: _fieldFontSize);

  /// Every line of the field is exactly this box, whatever the font's own
  /// metrics would make it.
  StrutStyle get _fieldStrut => StrutStyle(
    fontFamily: PTFonts.body,
    fontSize: _fieldFontSize,
    height: _kFieldLineHeight,
    leadingDistribution: .even,
    forceStrutHeight: true,
  );

  Widget _field({required bool tight}) => TextField(
    controller: _controller,
    focusNode: _inputFocus,
    textInputAction: .send,
    onChanged: (text) {
      _onTextChanged(text);
      // Only the counter depends on it, and only near the limit.
      if (text.runes.length >= _kCounterFrom - 1) setState(() {});
    },
    // Touch: tapping the field brings the keyboard back, so the inline picker
    // makes way for it.
    onTap: () {
      if (_touch && _pickerOpen) _closePicker(keyboardFollows: true);
    },
    // The default `onEditingComplete` unfocuses on submit; `_send`
    // owns focus instead. `onSubmitted` still fires after it.
    onEditingComplete: () {},
    onSubmitted: (_) => _send(),
    // Codepoints, not `maxLength`'s graphemes - see [chatLengthOk].
    inputFormatters: const [_CodepointLimitFormatter()],
    // Grows with what is typed (and with the text scale), up to
    // four lines, then scrolls. `.send` still makes Enter send.
    minLines: 1,
    maxLines: tight ? 2 : 4,
    keyboardType: .multiline,
    style: _fieldStyle,
    strutStyle: _fieldStrut,
    cursorColor: PTColors.textAccent,
    decoration: InputDecoration(
      hintText: 'Say something…',
      hintStyle: PTText.body.copyWith(fontSize: _spare ? 13 : 15, color: PTColors.fgMute),
      border: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.fromLTRB(4, 0, _spare ? 12 : 14, 0),
    ),
  );

  /// Unlit until there is something to send, then Beam - the one lit thing
  /// in the panel. Listens to the controller itself, so typing rebuilds only
  /// this button.
  Widget _sendButton() => ValueListenableBuilder(
    valueListenable: _controller,
    builder: (context, value, _) {
      final lit = value.text.trim().isNotEmpty;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: PTPressable(
          onTap: _send,
          pressedScale: 0.92,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            curve: PTMotion.enter,
            width: _kSendExtent,
            height: _kSendExtent,
            decoration: BoxDecoration(
              color: lit ? PTColors.primary : Colors.transparent,
              border: Border.all(color: lit ? PTColors.primary : PTColors.rail),
              borderRadius: BorderRadius.circular(PTRadius.control),
              boxShadow: lit ? PTColors.beamSpill : const [],
            ),
            child: Icon(
              BoothIcons.send,
              size: 19,
              fill: 1,
              color: lit ? PTColors.onAccent : PTColors.white(0.5),
            ),
          ),
        ),
      );
    },
  );

  /// Pointer: a popover above the composer's leading edge, sized to and
  /// kept inside the window rather than the panel (a floating panel can be
  /// shorter than the picker is useful at, and the overlay is not clipped by it).
  Widget _popover(BuildContext context, OverlayChildLayoutInfo info) {
    const gap = 6.0;
    const margin = 8.0;
    final overlay = info.overlaySize;
    final anchor = MatrixUtils.transformPoint(info.childPaintTransform, Offset.zero);
    // Inside the composer's width when it can be (a docked panel is ~340
    // wide), never narrower than a usable grid, never wider than the window.
    final width = math.min(
      math.min(340.0, math.max(280.0, info.childSize.width - 2 * margin)),
      overlay.width - 2 * margin,
    );
    final height = math.min(380.0, math.max(160.0, anchor.dy - gap - margin));
    final left = math.min(anchor.dx + margin, math.max(margin, overlay.width - width - margin));
    final bottom = math.max(margin, overlay.height - anchor.dy + gap);
    return Positioned(
      left: left,
      bottom: bottom,
      width: width,
      height: height,
      // Offstage while warming (see [_hoverEnter]): laid out, never painted
      // or hit-tested.
      child: Offstage(
        offstage: !_pickerOpen,
        child: TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) => _closePicker(),
          child: MouseRegion(
            onEnter: (_) => _hoverClose?.cancel(),
            onExit: (_) => _hoverExit(),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onComposerKey,
              // Popover entrance: scale in cleanly.
              // Animates 0 -> 1 when [_pickerOpen] flips, not at mount, since
              // a warmed picker mounts before it is revealed.
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _pickerOpen ? 1 : 0),
                duration: PTMotion.functional(context, PTMotion.state),
                curve: PTMotion.enter,
                builder: (context, t, child) => Transform.translate(
                  offset: Offset(0, 8 * (1 - t)),
                  child: Transform.scale(
                    scale: 0.94 + 0.06 * t,
                    alignment: .bottomLeft,
                    child: child,
                  ),
                ),
                child: GlassPanel(
                  radius: 18,
                  baseColor: PTColors.surfaceBase,
                  // Its own layer: the entrance transform then moves a cached
                  // picture instead of repainting every glyph each frame.
                  child: RepaintBoundary(
                    child: EmojiPicker(
                      prefs: _emoji,
                      onPick: _insert,
                      onCustomize: () => _customize(0),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The picker is laid out at the height it will settle at and revealed from
  /// the top, [shown] tall, as the keyboard leaves: a slide in, with nothing
  /// re-laid-out per frame. The clip also stops hits below the reveal.
  ///
  /// With no keyboard to trade with, [reveal] (0..1) unfolds the same strip
  /// over [PTMotion.panel]: the clip grows (content is never rescaled), the
  /// layout delegate hands the composer the same animated height, and the
  /// picker takes no hits until it has settled. Only the clip rebuilds per
  /// frame - the grid is built once.
  Widget _inlinePicker(double shown, ValueListenable<double> reveal) {
    // An opaque tap sink: a tap in the gaps of the grid must not count as
    // "empty space" ([EmptyTapHook]) and close the picker under the finger.
    final body = GestureDetector(
      behavior: .opaque,
      onTap: () {},
      child: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: PTColors.white(0.08))),
        ),
        child: EmojiPicker(prefs: _emoji, onPick: _insert, onCustomize: () => _customize(0)),
      ),
    );
    return ValueListenableBuilder<double>(
      valueListenable: reveal,
      child: body,
      builder: (context, t, child) => IgnorePointer(
        ignoring: t < 1 || _pickerClosing,
        child: ClipRect(clipper: _RevealClip(shown * t), child: child),
      ),
    );
  }

  Widget _typingRow() {
    final names = widget.typingNames;
    final label = names.length == 1
        ? '${names.first} is typing'
        : names.length == 2
        ? '${names[0]}, ${names[1]} are typing'
        : 'Several people are typing';
    return AnimatedSize(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      alignment: .topLeft,
      child: names.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                spacing: 8,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: PTText.finePrint.copyWith(
                        fontStyle: .italic,
                        color: PTColors.white(0.5),
                      ),
                    ),
                  ),
                  const TypingDots(),
                ],
              ),
            ),
    );
  }
}

class _MessageRow extends StatefulWidget {
  const _MessageRow({
    required this.message,
    required this.own,
    required this.premium,
    this.frame,
    required this.onCopied,
    required this.onPlaySharedVideo,
    this.onReport,
    this.spare = false,
  });

  final ChatMessage message;
  final bool own;

  /// The floating desktop panel's smaller type and padding.
  final bool spare;
  final bool premium;
  final AvatarFrame? frame;
  final VoidCallback onCopied;
  final void Function(String videoId, String sharedBy)? onPlaySharedVideo;
  final ValueChanged<ChatMessage>? onReport;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow> {
  bool _hovered = false;
  late List<MessageSegment> _segments;

  /// One to three emoji and nothing else: rendered large, with no bubble.
  bool _bigEmoji = false;
  final _linkTaps = <int, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _parseContent();
  }

  @override
  void didUpdateWidget(covariant _MessageRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.content != widget.message.content) _parseContent();
  }

  @override
  void dispose() {
    _disposeLinkTaps();
    super.dispose();
  }

  void _disposeLinkTaps() {
    for (final recognizer in _linkTaps.values) {
      recognizer.dispose();
    }
    _linkTaps.clear();
  }

  void _parseContent() {
    _disposeLinkTaps();
    _segments = splitYouTubeLinks(widget.message.content);
    _bigEmoji = isEmojiOnly(widget.message.content);
    for (var i = 0; i < _segments.length; i++) {
      final videoId = _segments[i].videoId;
      if (videoId == null) continue;
      _linkTaps[i] = TapGestureRecognizer()..onTap = () => _play(videoId);
    }
  }

  void _play(String videoId) {
    widget.onPlaySharedVideo?.call(videoId, widget.message.displayName);
  }

  EdgeInsets get _bubblePadding => widget.spare
      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
      : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);

  bool get _actionable => widget.onPlaySharedVideo != null && _linkTaps.isNotEmpty;

  String? get _soleVideoId {
    final ids = _segments.map((segment) => segment.videoId).nonNulls.toSet();
    return ids.length == 1 ? ids.single : null;
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.message.content));
    widget.onCopied();
  }

  Widget _text() {
    if (_bigEmoji) {
      return Text(widget.message.content.trim(), style: PTText.emoji.copyWith(fontSize: 34));
    }
    // Your own lines are printed on paper - Screen with Booth ink.
    final base = PTText.body.copyWith(
      fontSize: widget.spare ? 13 : 15,
      height: 1.35,
      color: widget.own ? PTColors.canvas : PTColors.fg,
    );
    if (_linkTaps.isEmpty) return Text(widget.message.content, style: base);
    final linkColor = widget.own ? PTColors.liveInk : PTColors.textAccent;
    final linkStyle = base.copyWith(
      color: linkColor,
      fontWeight: .w500,
      decoration: _actionable ? TextDecoration.underline : null,
      decorationColor: linkColor.withValues(alpha: 0.45),
    );
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < _segments.length; i++)
            if (_segments[i].videoId == null)
              TextSpan(text: _segments[i].text)
            else
              TextSpan(
                text: _segments[i].text,
                style: linkStyle,
                recognizer: _actionable ? _linkTaps[i] : null,
                mouseCursor: _actionable ? SystemMouseCursors.click : null,
              ),
        ],
      ),
      style: base,
    );
  }

  Widget _bubbleBody() {
    final videoId = _actionable ? _soleVideoId : null;
    if (videoId == null) return _text();
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        _text(),
        _PlaySharedVideoButton(own: widget.own, onTap: () => _play(videoId)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pointer: actions appear on hover. Touch has no hover, and permanently
    // visible icons beside every bubble read as clutter, so a tap on the
    // message reveals them instead (long-press stays text selection).
    final copyButton = _action(
      PTIconButton(
        icon: Symbols.content_copy_rounded,
        onPressed: _copy,
        size: 26,
        iconSize: 15,
        glass: false,
        color: PTColors.white(0.55),
        tooltip: 'Copy message',
      ),
    );

    final reportButton = widget.onReport != null
        ? _action(
            PTIconButton(
              icon: BoothIcons.flag,
              onPressed: () => widget.onReport!(widget.message),
              size: 26,
              iconSize: 15,
              glass: false,
              color: PTColors.white(0.45),
              tooltip: 'Report message',
            ),
          )
        : null;

    final row = widget.own ? _own(copyButton) : _other(copyButton, reportButton);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: isDesktop
          ? row
          : GestureDetector(
              behavior: .translucent,
              onTap: () => setState(() => _hovered = !_hovered),
              child: row,
            ),
    );
  }

  /// A per-message action: invisible and untappable until revealed.
  Widget _action(Widget button) => IgnorePointer(
    ignoring: !_hovered,
    child: AnimatedOpacity(
      duration: PTMotion.functional(context, PTMotion.hover),
      opacity: _hovered ? 1 : 0,
      child: button,
    ),
  );

  Widget _other(Widget copyButton, Widget? reportButton) {
    final message = widget.message;
    return Row(
      crossAxisAlignment: .end,
      spacing: 8,
      children: [
        PTAvatar(
          userId: message.senderId,
          displayName: message.displayName,
          size: 26,
          premium: widget.premium,
          frame: widget.frame,
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 3,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  message.displayName,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(
                    fontFamily: PTFonts.body,
                    fontSize: 12,
                    fontWeight: .w600,
                    color: PTColors.fgSoft,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: _bigEmoji ? const EdgeInsets.symmetric(horizontal: 2) : _bubblePadding,
                decoration: _bigEmoji
                    ? null
                    : const BoxDecoration(
                        color: PTColors.aisle,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(PTRadius.panel),
                          topRight: Radius.circular(PTRadius.panel),
                          bottomRight: Radius.circular(PTRadius.panel),
                          bottomLeft: Radius.circular(2),
                        ),
                      ),
                child: _bubbleBody(),
              ),
            ],
          ),
        ),
        // Stacked, not side by side: two 26 px buttons in a row cost a 300 px
        // docked panel a third of its bubble width.
        Column(mainAxisSize: .min, children: [copyButton, ?reportButton]),
      ],
    );
  }

  Widget _own(Widget copyButton) {
    return Row(
      mainAxisAlignment: .end,
      crossAxisAlignment: .end,
      spacing: 8,
      children: [
        copyButton,
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: _bigEmoji ? const EdgeInsets.symmetric(horizontal: 2) : _bubblePadding,
            decoration: _bigEmoji
                ? null
                : const BoxDecoration(
                    color: PTColors.fg,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(PTRadius.panel),
                      topRight: Radius.circular(PTRadius.panel),
                      bottomLeft: Radius.circular(PTRadius.panel),
                      bottomRight: Radius.circular(2),
                    ),
                  ),
            child: _bubbleBody(),
          ),
        ),
      ],
    );
  }
}

class _PlaySharedVideoButton extends StatefulWidget {
  const _PlaySharedVideoButton({required this.own, required this.onTap});

  final bool own;
  final VoidCallback onTap;

  @override
  State<_PlaySharedVideoButton> createState() => _PlaySharedVideoButtonState();
}

class _PlaySharedVideoButtonState extends State<_PlaySharedVideoButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tint = widget.own ? PTColors.canvas : PTColors.textAccent;
    final fill = widget.own
        ? PTColors.canvas.withValues(alpha: _hovered ? 0.16 : 0.08)
        : PTColors.primary.withValues(alpha: _hovered ? 0.38 : 0.24);
    return SelectionContainer.disabled(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: PTPressable(
          onTap: widget.onTap,
          pressedScale: 0.97,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: tint.withValues(alpha: 0.34)),
              borderRadius: BorderRadius.circular(PTRadius.control),
            ),
            child: Row(
              mainAxisSize: .min,
              mainAxisAlignment: .center,
              spacing: 6,
              children: [
                Icon(Symbols.play_circle_rounded, size: 16, fill: 1, color: tint),
                Flexible(
                  child: Text(
                    'Play for everyone',
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: PTText.caption.copyWith(fontSize: 12, color: tint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Scroll physics for chat panels that keeps the scroll position anchored to the
/// bottom when the viewport height changes (e.g. control bar animating in/out,
/// keyboard opening/closing, or window resizing), as long as the user was already
/// near the bottom.
enum _ComposerSlot { list, composer, picker }

class _RevealClip extends CustomClipper<Rect> {
  const _RevealClip(this.shown);

  final double shown;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, math.min(shown, size.height));

  @override
  bool shouldReclip(_RevealClip old) => old.shown != shown;
}

class _ComposerLayout extends MultiChildLayoutDelegate {
  _ComposerLayout({required this.picker, required this.body, required this.reveal})
    : super(relayout: reveal);

  /// 0..1: how much of [picker] is unfolded (1 unless it opens or closes with
  /// no keyboard to trade places with). Listened to, so the fold re-runs
  /// layout alone, without rebuilding the list.
  final ValueListenable<double> reveal;

  /// The picker's height once the keyboard has left (before trimming).
  final double body;

  /// The inline picker's wanted height, or null when it is not shown.
  final double? picker;

  /// What the message list keeps, at least, while the picker is up.
  static const _minList = 48.0;

  @override
  void performLayout(Size size) {
    final width = size.width;
    final composer = layoutChild(
      _ComposerSlot.composer,
      // Unbounded: the header above may still be folding away while the panel
      // is already at its floor. The composer then keeps its place against the
      // bottom edge (the keyboard) and overlaps the header's last pixels,
      // rather than overflowing or sinking below them.
      BoxConstraints(minWidth: width, maxWidth: width),
    ).height;
    var pickerHeight = 0.0;
    if (picker != null) {
      pickerHeight = math.max(
        0.0,
        math.min(picker! * reveal.value, size.height - composer - _minList),
      );
      // Laid out at what it settles at: the area without the picker's slice,
      // less the composer and the list's least, capped at its own body.
      final settled = math.max(0.0, math.min(body, size.height - picker! - composer - _minList));
      layoutChild(
        _ComposerSlot.picker,
        BoxConstraints.tightFor(width: width, height: math.max(settled, pickerHeight)),
      );
    }
    final list = math.max(0.0, size.height - composer - pickerHeight);
    layoutChild(_ComposerSlot.list, BoxConstraints.tightFor(width: width, height: list));
    positionChild(_ComposerSlot.list, Offset.zero);
    positionChild(_ComposerSlot.composer, Offset(0, size.height - composer - pickerHeight));
    if (picker != null) positionChild(_ComposerSlot.picker, Offset(0, size.height - pickerHeight));
  }

  @override
  bool shouldRelayout(_ComposerLayout oldDelegate) =>
      oldDelegate.picker != picker || oldDelegate.body != body || oldDelegate.reveal != reveal;
}

/// Refuses an edit that would take the message past the server's codepoint
/// limit. A paste that overshoots is refused whole rather than truncated, since
/// cutting inside a ZWJ sequence would leave half an emoji behind.
class _CodepointLimitFormatter extends TextInputFormatter {
  const _CodepointLimitFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      chatLengthOk(newValue.text) || newValue.text.runes.length <= oldValue.text.runes.length
      ? newValue
      : oldValue;
}

class ChatScrollPhysics extends ScrollPhysics {
  const ChatScrollPhysics({super.parent, this.bottomThreshold = 80.0});

  final double bottomThreshold;

  @override
  ChatScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ChatScrollPhysics(parent: buildParent(ancestor), bottomThreshold: bottomThreshold);
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final oldRemaining = oldPosition.maxScrollExtent - oldPosition.pixels;
    if (!isScrolling &&
        velocity == 0.0 &&
        oldRemaining >= 0 &&
        oldRemaining <= bottomThreshold &&
        oldPosition.viewportDimension != newPosition.viewportDimension) {
      final target = newPosition.maxScrollExtent - oldRemaining;
      return target.clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent);
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}
