import 'package:flutter/services.dart';

/// What happened when we asked the system calendar to add an event.
enum CalendarResult {
  /// The person saved it (iOS tells us).
  added,

  /// The system sheet opened. Android does not report whether it was saved.
  opened,

  /// The person closed the sheet without saving.
  dismissed,

  /// This platform has no native add-to-calendar, or access was refused: the
  /// caller falls back to sharing a calendar file.
  unsupported,
}

/// The system's own "add this event" sheet, behind an interface so the screens
/// above it are tested with no device. iOS presents EventKitUI's event editor and
/// Android launches the calendar app's insert screen; neither needs this app to
/// read anyone's calendar, which is why it asks for nothing on iOS 17+ and
/// nothing at all on Android. Desktop has no equivalent: `unsupported`.
abstract class CalendarBridge {
  Future<CalendarResult> addEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String? notes,
  });
}

class ChannelCalendarBridge implements CalendarBridge {
  static const _channel = MethodChannel('app.synctogether/calendar');

  @override
  Future<CalendarResult> addEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String? notes,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('addEvent', {
        'title': title,
        'start': start.toUtc().millisecondsSinceEpoch,
        'end': end.toUtc().millisecondsSinceEpoch,
        'notes': notes,
      });
      return switch (result) {
        'added' => CalendarResult.added,
        'opened' => CalendarResult.opened,
        'dismissed' => CalendarResult.dismissed,
        _ => CalendarResult.unsupported,
      };
    } on MissingPluginException {
      return CalendarResult.unsupported;
    } on PlatformException {
      return CalendarResult.unsupported;
    }
  }
}

/// Swapped in tests.
CalendarBridge calendarBridge = ChannelCalendarBridge();
