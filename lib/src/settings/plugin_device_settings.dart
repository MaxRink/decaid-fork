import 'package:reaprime/src/plugins/plugin_device_contract.dart';
import 'package:reaprime/src/util/safe_path.dart';

Uri pluginDeviceSettingsUri({
  required String pluginId,
  required String endpointId,
  required String deviceId,
  String? deviceName,
}) {
  if (!isSafePathComponent(pluginId) || !isSafePathComponent(endpointId)) {
    throw ArgumentError('Invalid plugin settings endpoint');
  }
  final queryParameters = {'ui': '1', 'deviceId': deviceId};
  if (deviceName case final name?) queryParameters['deviceName'] = name;
  return Uri(
    scheme: 'http',
    host: 'localhost',
    port: 8080,
    pathSegments: ['api', 'v1', 'plugins', pluginId, endpointId],
    queryParameters: queryParameters,
  );
}

Uri pluginDeviceSettingsUriForDevice(DeviceSettingsCapable device) {
  final settings = device.deviceSettings;
  if (settings == null) throw ArgumentError('Device has no settings endpoint');
  return pluginDeviceSettingsUri(
    pluginId: settings.pluginId,
    endpointId: settings.endpointId,
    deviceId: device.deviceId,
    deviceName: device.name,
  );
}
