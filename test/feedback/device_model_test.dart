import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/feedback/capture/device_model.dart';

void main() {
  setUp(DeviceModel.debugReset);

  test('the model is read once and cached', () async {
    var calls = 0;
    DeviceModel.lookup = () async {
      calls++;
      return 'iPhone 17';
    };
    expect(await DeviceModel.read(), 'iPhone 17');
    expect(await DeviceModel.read(), 'iPhone 17');
    expect(calls, 1);
  });

  test('any failure leaves the model out instead of failing the report', () async {
    DeviceModel.lookup = () async => throw StateError('no plugin');
    expect(await DeviceModel.read(), isNull);
  });

  test('an empty answer is no model', () async {
    DeviceModel.lookup = () async => '   ';
    expect(await DeviceModel.read(), isNull);
  });

  test('emails and paths never ride along in a model name', () async {
    DeviceModel.lookup = () async => 'anna@example.com /Users/anna/Phone';
    final model = await DeviceModel.read();
    expect(model, isNot(contains('@')));
    expect(model, isNot(contains('/Users')));
  });

  test('Android names put the manufacturer first unless the model already has it', () {
    expect(DeviceModel.androidName('samsung', 'SM-S921B'), 'Samsung SM-S921B');
    expect(DeviceModel.androidName('Google', 'Pixel 8'), 'Google Pixel 8');
    expect(DeviceModel.androidName('OnePlus', 'OnePlus 12'), 'OnePlus 12');
    expect(DeviceModel.androidName('', 'Pixel 8'), 'Pixel 8');
    expect(DeviceModel.androidName('Xiaomi', ''), 'Xiaomi');
  });
}
