import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/open_failure.dart';

void main() {
  test('what mpv says is sorted into three kinds', () {
    expect(classifyOpenFailure('Failed to recognize file format.'), OpenFailure.format);
    expect(
      classifyOpenFailure("Failed to initialize a decoder for codec 'hevc'."),
      OpenFailure.format,
    );
    expect(classifyOpenFailure('Operation not permitted'), OpenFailure.unreadable);
    expect(classifyOpenFailure('open: Permission denied'), OpenFailure.unreadable);
    expect(classifyOpenFailure('never reported a length'), OpenFailure.stalled);
    expect(classifyOpenFailure(null), OpenFailure.stalled);
    expect(classifyOpenFailure('SOMETHING ELSE'), OpenFailure.stalled);
  });

  test('a thrown error is classified from its text, case aside', () {
    expect(
      classifyOpenFailure(Exception('FAILED TO RECOGNIZE FILE FORMAT').toString()),
      OpenFailure.format,
    );
  });
}
