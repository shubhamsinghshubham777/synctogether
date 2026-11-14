import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import 'shake_detector.dart';
import 'shake_source.dart';

typedef AccelerationSample = ({double x, double y, double z});

/// Android: no system gesture exists, so read the gravity-free accelerometer
/// and let [ShakeDetector] decide. Never constructed on iOS.
class AccelerometerShakeSource implements ShakeSource {
  AccelerometerShakeSource({
    Stream<AccelerationSample> Function()? sensor,
    Duration Function()? clock,
    ShakeDetector? detector,
  }) : _sensor = sensor ?? _realSensor,
       _clock = clock ?? _stopwatchClock(),
       _detector = detector ?? ShakeDetector();

  final Stream<AccelerationSample> Function() _sensor;
  final Duration Function() _clock;
  final ShakeDetector _detector;

  @override
  Stream<void> get shakes {
    _detector.reset();
    return _sensor().where((s) => _detector.add(s.x, s.y, s.z, _clock())).map<void>((_) {});
  }

  static Stream<AccelerationSample> _realSensor() =>
      userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .map((e) => (x: e.x, y: e.y, z: e.z));

  static Duration Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }
}
