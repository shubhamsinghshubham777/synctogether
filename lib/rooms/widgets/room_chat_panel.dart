import 'dart:async';
import '../../ui/booth_icons.g.dart';
import 'dart:math' as math;

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
import 'package:synctogether/ui/booth.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/identity.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';

import '../../rewards/rewards_models.dart';
import 'emoji_picker.dart';
import 'emoji_quick_bar.dart';

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
    this.premiumMembers = const {},
    this.memberFrames = const {},
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

  /// Embedded (mobile portrait) skips its own glass shell + close button.
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

  @override
  State<RoomChatPanel> createState() => _RoomChatPanelState();
}

/// One avatar in the chat panel's "In the room" roster.
class ChatRosterSeat {
  const ChatRosterSeat({
    required this.member,
    required this.ready,
    this.premium = false,
    this.frame,
  });

  final PresentMember member;
  final bool ready;
  final bool premium;
  final AvatarFrame? frame;
}

class _RoomChatPanelState extends State<RoomChatPanel> {
  final _controller = TextEditingController();
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
  double _keyboardHeight = 0;
  Size _panelSize = Size.zero;
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
  void dispose() {
    _typingDebounce?.cancel();
    _hoverOpen?.cancel();
    _hoverClose?.cancel();
    _controller.dispose();
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
    _closePicker();
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
      // The picker takes the keyboard's place rather than stacking on it.
      _inputFocus.unfocus();
    } else {
      _pickerPortal.show();
    }
    setState(() {
      _pickerOpen = true;
      _pickerPinned = pinned;
    });
  }

  void _closePicker() {
    _hoverOpen?.cancel();
    _hoverClose?.cancel();
    if (!_pickerOpen) return;
    _pickerPortal.hide();
    setState(() {
      _pickerOpen = false;
      _pickerPinned = false;
    });
  }

  void _togglePicker() {
    if (_pickerOpen && (_pickerPinned || _touch)) {
      _closePicker();
      // Touch: hand the keyboard back, which is why they closed it.
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
        _panelSize = constraints.biggest;
        // The panel resizes as the keyboard rises, so this builder sees it.
        // Read from the View: the Scaffold strips insets from what we inherit.
        final view = View.of(context);
        final keyboard = view.viewInsets.bottom / view.devicePixelRatio;
        if (keyboard > 0) _keyboardHeight = keyboard;
        return _content(
          // An inline picker needs the room more than the header does.
          showHeader: constraints.maxHeight >= (_pickerOpen && _touch ? 480 : 240),
          tight: constraints.maxHeight < 200,
          // The field and header grow with the text scale; the bar does not,
          // so the room it needs before appearing grows with them.
          quickBar:
              constraints.maxHeight >= 300 + 90 * (MediaQuery.textScalerOf(context).scale(1) - 1),
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

  Widget _content({required bool showHeader, required bool tight, required bool quickBar}) {
    return Column(
      children: [
        if (showHeader && widget.roster != null)
          _rosterHeader(widget.roster!)
        else if (showHeader)
          // The Room at minimum window board: "Chat" and a mono head count on
          // one Aisle-ruled line.
          Container(
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
          ),
        // One pass lays the composer out at its natural height, gives the
        // inline picker what is left of what it wants, and the list the rest -
        // exact on the first frame, which measuring a GlobalKey never is.
        Expanded(
          child: CustomMultiChildLayout(
            delegate: _ComposerLayout(picker: _pickerOpen && _touch ? _inlinePickerHeight() : null),
            children: [
              LayoutId(
                id: _ComposerSlot.list,
                child: SelectionArea(
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const ChatScrollPhysics(),
                    padding: _spare
                        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
                        : const EdgeInsets.all(20),
                    // The typing slot is always present so it can collapse rather than
                    // pop; its own gap lives inside it, which is why the separator
                    // before it is suppressed.
                    itemCount: widget.messages.length + 1,
                    separatorBuilder: (_, index) => index == widget.messages.length - 1
                        ? const SizedBox.shrink()
                        : SizedBox(height: _spare ? 10 : 14),
                    itemBuilder: (context, index) {
                      if (index == widget.messages.length) {
                        return _typingRow();
                      }
                      final message = widget.messages[index];
                      final bubble = _MessageRow(
                        message: message,
                        own: message.senderId == widget.sync.userId,
                        premium: widget.premiumMembers.contains(message.senderId),
                        frame: widget.memberFrames[message.senderId],
                        onCopied: widget.onCopied,
                        onPlaySharedVideo: widget.onPlaySharedVideo,
                        onReport: widget.onReportMessage,
                        spare: _spare,
                      );
                      final key = _keyOf(message);
                      if (!_animated.add(key)) return bubble;
                      return PTEntrance(duration: PTMotion.state, offset: 6, child: bubble);
                    },
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
              if (_pickerOpen && _touch) LayoutId(id: _ComposerSlot.picker, child: _inlinePicker()),
            ],
          ),
        ),
      ],
    );
  }

  /// "IN THE ROOM · 4" over a row of seats. One line that scrolls sideways
  /// rather than wrapping: a sixteen-seat room must not eat the chat's height.
  Widget _rosterHeader(List<ChatRosterSeat> seats) {
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
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: .horizontal,
              padding: EdgeInsets.zero,
              itemCount: seats.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final seat = seats[i];
                final m = seat.member;
                return Tooltip(
                  message: [
                    m.displayName,
                    if (m.isHost) 'host',
                    seat.ready ? 'ready' : 'getting ready',
                  ].join(' · '),
                  child: Center(
                    child: ReadyRing(
                      diameter: 36,
                      ready: seat.ready,
                      premium: seat.premium,
                      clip: false,
                      child: PTAvatar(
                        userId: m.userId,
                        displayName: m.displayName,
                        avatarUrl: m.avatarUrl,
                        size: 36,
                        premium: seat.premium,
                        frame: seat.frame,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
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
          if (quickBar)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EmojiQuickBar(slots: _quickSlots, onPick: _insert, onCustomize: _customize),
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
      if (_touch && _pickerOpen) _closePicker();
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

  /// Pointer: a glass popover above the composer's leading edge, sized to and
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
              // Glass rule: scale in, never fade - an Opacity over the
              // BackdropFilter would blur an empty layer.
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
                  opacity: 0.85,
                  blur: 32,
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

  /// Touch: in the keyboard's place, at the keyboard's last height so the
  /// composer does not jump between the two.
  /// Touch: the keyboard's last height, so the composer does not jump between
  /// the two; capped so the list keeps a share. [_ComposerLayout] trims it
  /// further if the composer leaves less.
  double _inlinePickerHeight() {
    final wanted = _keyboardHeight > 0 ? _keyboardHeight : 280.0;
    return math.min(wanted, _panelSize.height * 0.6) + MediaQuery.paddingOf(context).bottom;
  }

  Widget _inlinePicker() => Container(
    padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: PTColors.white(0.08))),
    ),
    child: EmojiPicker(prefs: _emoji, onPick: _insert, onCustomize: () => _customize(0)),
  );

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

class _ComposerLayout extends MultiChildLayoutDelegate {
  _ComposerLayout({required this.picker});

  /// The inline picker's wanted height, or null when it is not shown.
  final double? picker;

  /// What the message list keeps, at least, while the picker is up.
  static const _minList = 48.0;

  @override
  void performLayout(Size size) {
    final width = size.width;
    final composer = layoutChild(
      _ComposerSlot.composer,
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: size.height),
    ).height;
    var pickerHeight = 0.0;
    if (picker != null) {
      pickerHeight = math.max(0.0, math.min(picker!, size.height - composer - _minList));
      layoutChild(
        _ComposerSlot.picker,
        BoxConstraints.tightFor(width: width, height: pickerHeight),
      );
    }
    final list = math.max(0.0, size.height - composer - pickerHeight);
    layoutChild(_ComposerSlot.list, BoxConstraints.tightFor(width: width, height: list));
    positionChild(_ComposerSlot.list, Offset.zero);
    positionChild(_ComposerSlot.composer, Offset(0, list));
    if (picker != null) positionChild(_ComposerSlot.picker, Offset(0, list + composer));
  }

  @override
  bool shouldRelayout(_ComposerLayout oldDelegate) => oldDelegate.picker != picker;
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
