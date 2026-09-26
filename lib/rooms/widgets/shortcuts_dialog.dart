import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_theme.dart';

class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key, this.facecams = false});

  final bool facecams;

  static const _playback = <_Shortcut>[
    _Shortcut(['Space', 'K'], 'Play or pause'),
    _Shortcut(['J', 'L'], 'Back or forward 10s'),
    _Shortcut(['←', '→'], 'Back or forward 5s'),
  ];

  static const _audio = <_Shortcut>[
    _Shortcut(['↑', '↓'], 'Volume up or down'),
    _Shortcut(['M'], 'Mute or unmute'),
  ];

  @override
  Widget build(BuildContext context) {
    final view = <_Shortcut>[
      const _Shortcut(['H'], 'Show or hide room controls'),
      const _Shortcut(['C'], 'Show or hide the chat panel'),
      if (facecams) const _Shortcut(['V'], 'Show or hide the facecams'),
      if (facecams) const _Shortcut(['D'], 'Turn your mic on or off'),
      if (facecams) const _Shortcut(['E'], 'Turn your camera on or off'),
      const _Shortcut(['R'], 'Open or close the reactions tray'),
      if (isDesktop) const _Shortcut(['F'], 'Enter or exit fullscreen'),
      const _Shortcut(['F1'], 'Privacy mode: black out the room, mute mic and cam'),
      if (kDebugMode) const _Shortcut(['F2'], 'Debug: Simulate / toggle YouTube ad'),
      const _Shortcut(['?'], 'Show keyboard shortcuts'),
      _Shortcut([
        defaultTargetPlatform == TargetPlatform.macOS ? '⌘E' : 'Ctrl+E',
      ], 'Open or close emoji (while typing in chat)'),
      const _Shortcut(['Esc'], 'Close emoji, then the reaction strip, then chat, then fullscreen'),
    ];

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        GlassDialogHeader(
          eyebrow: 'The booth controls',
          title: 'Keyboard shortcuts',
          subtitle: 'Quiet while you type in chat.',
          titleGap: 5,
          subtitleStyle: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.6)),
        ),
        const SizedBox(height: 20),
        // No Flexible: showGlassDialog scrolls the whole body, and a flex
        // child inside that scroll view would have no height to divide.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 18,
              children: [
                _Section(title: 'Playback', shortcuts: _playback),
                _Section(title: 'Audio', shortcuts: _audio),
                _Section(title: 'View', shortcuts: view),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        PTButton(
          maxLines: 2,
          label: 'Got it',
          icon: Symbols.check_rounded,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _Shortcut {
  const _Shortcut(this.keys, this.description);

  final List<String> keys;
  final String description;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.shortcuts});

  final String title;
  final List<_Shortcut> shortcuts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 6),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: PTColors.rail)),
          ),
          child: Text(title.toUpperCase(), style: PTText.label),
        ),
        // Two columns wherever each still fits a keycap pair and a label;
        // a single column on a phone or at large text.
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= MediaQuery.textScalerOf(context).scale(440) ? 2 : 1;
            final cell = (box.maxWidth - 16 * (columns - 1)) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                for (final shortcut in shortcuts)
                  SizedBox(
                    width: cell,
                    child: _ShortcutRow(shortcut: shortcut),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.shortcut});

  final _Shortcut shortcut;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        SizedBox(
          width: 92,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final key in shortcut.keys) _KeyCap(label: key)],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              shortcut.description,
              style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.75)),
            ),
          ),
        ),
      ],
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: .center,
      decoration: BoxDecoration(
        color: PTColors.aisle,
        border: const Border(
          top: BorderSide(color: PTColors.rail),
          left: BorderSide(color: PTColors.rail),
          right: BorderSide(color: PTColors.rail),
          bottom: BorderSide(color: PTColors.rail, width: 2),
        ),
        borderRadius: BorderRadius.circular(PTRadius.control),
      ),
      child: Text(label, style: PTText.mono.copyWith(fontSize: 11.5, color: PTColors.fg)),
    );
  }
}
