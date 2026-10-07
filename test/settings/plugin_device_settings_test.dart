import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/plugin_device_settings.dart';

void main() {
  test('builds a device settings URI with encoded identity', () {
    final uri = pluginDeviceSettingsUri(
      pluginId: 'skale.reaplugin',
      endpointId: 'device-settings',
      deviceId: 'plugin:skale.reaplugin:skale:one two',
      deviceName: 'Skale #1',
    );
    expect(uri.pathSegments, [
      'api',
      'v1',
      'plugins',
      'skale.reaplugin',
      'device-settings',
    ]);
    expect(
      uri.queryParameters['deviceId'],
      'plugin:skale.reaplugin:skale:one two',
    );
    expect(uri.queryParameters['deviceName'], 'Skale #1');
    expect(uri.queryParameters['ui'], '1');
  });
}
