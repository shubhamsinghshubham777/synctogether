import 'package:synctogether/ui/pt_date_time_picker.dart';

import '../support/screen_matrix.dart';
import 'layout_support.dart';

/// The date and time picker at every device shape and text size: wheels under
/// 480 wide or tall, the month grid otherwise, as a sheet on a phone and a dialog
/// elsewhere. Variants cover the longest strings it can show.
void main() {
  final now = DateTime.now();
  final soon = DateTime(now.year, now.month, now.day + 3, 21, 0);

  void picker(
    String name, {
    bool dateOnly = false,
    DateTime? initial,
    DateTime? max,
    String? movingFrom,
    String? Function(DateTime)? partnerLine,
  }) {
    screenMatrix('date-time-picker/$name', (tester, c, s) async {
      await pumpDialogOpener(
        tester,
        c,
        s,
        (context) => showPTDateTimePicker(
          context,
          initial: initial ?? soon,
          min: now,
          max: max ?? now.add(const Duration(days: 365)),
          dateOnly: dateOnly,
          movingFrom: movingFrom,
          partnerLine: partnerLine,
        ),
      );
      await finishCase(tester);
    });
  }

  picker('default');
  picker('date-only', dateOnly: true);
  picker(
    'partner-and-moving',
    movingFrom: 'Moving from Wednesday 30 September, 11:59 PM',
    partnerLine: (_) => "That's 11:59 PM on Wednesday for Maximiliana.",
  );
  picker('last-day', initial: now.add(const Duration(days: 365)));
}
