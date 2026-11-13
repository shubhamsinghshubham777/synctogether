import 'contract.dart';
import 'fake_feedback_service.dart';

/// The active [FeedbackService]. Same pattern as `RoomService.instance`: a
/// mutable static so tests swap it. Defaults to the fake until W1 lands the
/// real implementation; `main.dart` assigns the real one at startup.
class FeedbackServices {
  FeedbackServices._();
  static FeedbackService instance = FakeFeedbackService();
}
