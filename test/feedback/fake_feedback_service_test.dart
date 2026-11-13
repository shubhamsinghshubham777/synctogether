import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/feedback/contract.dart';
import 'package:synctogether/feedback/fake_feedback_service.dart';

void main() {
  test('submit returns a code and shows up in watchMine', () async {
    final s = FakeFeedbackService();
    final rows = s.watchMine().take(2).toList();
    final r = await s.submit(
      const BugCapture(screenRoute: '/lobby'),
      category: .video,
      note: 'black',
      includeScreenshot: true,
    );
    expect(r, isA<Sent>());
    final all = await rows;
    expect(all.last.single.code, (r as Sent).code);
    expect(all.last.single.status, BugStatus.received);
  });
}
