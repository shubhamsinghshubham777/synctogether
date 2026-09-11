import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

Future<void> showDeviceSelectorPopup({
  required BuildContext context,
  required Rect anchor,
  required String title,
  required IconData icon,
  required Future<List<lk.MediaDevice>> Function() enumerateDevices,
  required String? selectedDeviceId,
  required ValueChanged<lk.MediaDevice> onDeviceSelected,
  Stream<List<lk.MediaDevice>>? onDeviceChange,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'device selector',
    barrierColor: Colors.transparent,
    transitionDuration: PTMotion.state,
    pageBuilder: (dialogContext, _, _) {
      final screenSize = MediaQuery.sizeOf(dialogContext);
      const width = 280.0;
      final left = (anchor.center.dx - width / 2).clamp(16.0, screenSize.width - width - 16.0);
      final bottom = screenSize.height - anchor.top + 8.0;

      return Stack(
        children: [
          Positioned(
            left: left,
            bottom: bottom,
            width: width,
            child: Material(
              type: .transparency,
              child: _DeviceSelectorPanel(
                title: title,
                icon: icon,
                enumerateDevices: enumerateDevices,
                selectedDeviceId: selectedDeviceId,
                onDeviceSelected: (device) {
                  onDeviceSelected(device);
                  Navigator.of(dialogContext).pop();
                },
                onDeviceChange: onDeviceChange,
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: PTMotion.enter,
        reverseCurve: PTMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _DeviceSelectorPanel extends StatefulWidget {
  const _DeviceSelectorPanel({
    required this.title,
    required this.icon,
    required this.enumerateDevices,
    required this.selectedDeviceId,
    required this.onDeviceSelected,
    this.onDeviceChange,
  });

  final String title;
  final IconData icon;
  final Future<List<lk.MediaDevice>> Function() enumerateDevices;
  final String? selectedDeviceId;
  final ValueChanged<lk.MediaDevice> onDeviceSelected;
  final Stream<List<lk.MediaDevice>>? onDeviceChange;

  @override
  State<_DeviceSelectorPanel> createState() => _DeviceSelectorPanelState();
}

class _DeviceSelectorPanelState extends State<_DeviceSelectorPanel> {
  List<lk.MediaDevice>? _devices;
  bool _loading = true;
  StreamSubscription<List<lk.MediaDevice>>? _sub;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _sub = widget.onDeviceChange?.listen((_) => _loadDevices());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await widget.enumerateDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _devices = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 20,
      opacity: 0.78,
      blur: 32,
      baseColor: const Color(0xFF141022),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 18, color: PTColors.textAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: PTText.panelHeading.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: PTColors.white(0.08)),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: PTLoader(size: 20)),
            )
          else if (_devices == null || _devices!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No devices found',
                  style: PTText.finePrint.copyWith(color: PTColors.white(0.5)),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: .min,
                  spacing: 4,
                  children: _devices!.map((device) {
                    final label = device.label.trim().isEmpty ? 'Default Device' : device.label;
                    final isSelected = device.deviceId == widget.selectedDeviceId;
                    return _DeviceRow(
                      label: label,
                      isSelected: isSelected,
                      onTap: () => widget.onDeviceSelected(device),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatefulWidget {
  const _DeviceRow({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends State<_DeviceRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: .opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? PTColors.primary.withValues(alpha: 0.22)
                : _hovered
                ? PTColors.white(0.07)
                : Colors.transparent,
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFFA78BFA).withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PTText.body.copyWith(
                    fontSize: 13,
                    color: widget.isSelected ? Colors.white : PTColors.white(0.85),
                    fontWeight: widget.isSelected ? .w600 : .w400,
                  ),
                ),
              ),
              if (widget.isSelected) ...[
                const SizedBox(width: 8),
                const Icon(
                  Symbols.check_circle_rounded,
                  size: 16,
                  fill: 1,
                  color: PTColors.textAccent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
