import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/plugins/plugin_device_contract.dart';
import 'package:reaprime/src/settings/device_management_page.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_settings_service.dart';
import '../helpers/test_scale.dart';

class _InformationScale extends TestScale
    implements DeviceInformationCapable, UsbPowerConfigurable {
  _InformationScale({
    required super.deviceId,
    required this.scaleName,
    required String firmwareVersion,
    int? batteryLevel,
  }) : _information = DeviceInformation(
         firmwareVersion: firmwareVersion,
         batteryLevel: batteryLevel,
       ),
       _informationSubject = BehaviorSubject<DeviceInformation?>.seeded(
         DeviceInformation(
           firmwareVersion: firmwareVersion,
           batteryLevel: batteryLevel,
         ),
       );

  final String scaleName;
  DeviceInformation? _information;
  final BehaviorSubject<DeviceInformation?> _informationSubject;
  bool poweredByUsb = false;

  @override
  String get name => scaleName;

  @override
  Future<void> setUsbPowered(bool value) async {
    poweredByUsb = value;
  }

  @override
  DeviceInformation? get currentDeviceInformation => _information;

  @override
  Stream<DeviceInformation?> get deviceInformation =>
      _informationSubject.stream;

  void emitFirmware(String firmwareVersion) {
    _information = DeviceInformation(firmwareVersion: firmwareVersion);
    _informationSubject.add(_information);
  }
}

class _SettingsScale extends _InformationScale
    implements DeviceSettingsCapable {
  _SettingsScale({required super.deviceId})
    : super(firmwareVersion: 'R029', scaleName: 'Settings scale');

  @override
  PluginDeviceSettings get deviceSettings => const PluginDeviceSettings(
    pluginId: 'test.plugin',
    endpointId: 'device-settings',
  );
}

class _InvalidSettingsScale extends _SettingsScale {
  _InvalidSettingsScale({required super.deviceId});

  @override
  PluginDeviceSettings get deviceSettings => const PluginDeviceSettings(
    pluginId: 'invalid/plugin',
    endpointId: 'device-settings',
  );
}

void main() {
  testWidgets('shows firmware and follows a same-ID replacement scale', (
    tester,
  ) async {
    final discovery = MockDeviceDiscoveryService();
    final settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();
    final deviceController = DeviceController([
      discovery,
    ], settingsController: settingsController);
    await deviceController.initialize();

    final first = _InformationScale(
      deviceId: 'skale-device',
      scaleName: 'Scale A',
      firmwareVersion: 'R029',
      batteryLevel: 82,
    );
    final second = _InformationScale(
      deviceId: 'other-skale-device',
      scaleName: 'Scale B',
      firmwareVersion: 'R028',
    );
    discovery.addDevice(first);
    discovery.addDevice(second);

    await tester.pumpWidget(
      ShadApp(
        home: DeviceManagementPage(
          settingsController: settingsController,
          deviceController: deviceController,
        ),
      ),
    );
    await tester.pump();

    Finder firmware(String section, String version) => find.descendant(
      of: find.ancestor(
        of: find.text(section),
        matching: find.byType(ShadCard),
      ),
      matching: find.textContaining('Firmware: $version'),
    );
    expect(firmware('Auto-connect Scale', 'R029'), findsOneWidget);
    expect(firmware('Dosing Scale', 'R029'), findsOneWidget);
    expect(
      find.textContaining('Battery: 82% (device-reported)'),
      findsNWidgets(2),
    );
    expect(find.text('Powered by USB'), findsNothing);
    expect(find.byTooltip('Configure Scale A'), findsNWidgets(2));
    expect(find.byTooltip('Configure Scale B'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Configure Scale B').first);
    await tester.pumpAndSettle();

    expect(find.text('Scale B settings'), findsOneWidget);
    final switchFinder = find.widgetWithText(SwitchListTile, 'Powered by USB');
    expect(switchFinder, findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pump();
    expect(
      settingsController.isSkalePoweredByUsb('other-skale-device'),
      isTrue,
    );
    expect(settingsController.isSkalePoweredByUsb('skale-device'), isFalse);
    expect(second.poweredByUsb, isTrue);
    expect(first.poweredByUsb, isFalse);

    discovery.clear();
    final replacement = _InformationScale(
      deviceId: 'skale-device',
      scaleName: 'Scale A',
      firmwareVersion: 'R030',
    );
    discovery.addDevice(replacement);
    await tester.pump();
    await tester.pump();

    expect(firmware('Auto-connect Scale', 'R030'), findsOneWidget);
    expect(firmware('Dosing Scale', 'R030'), findsOneWidget);

    replacement.emitFirmware('R031');
    await tester.pump();

    expect(firmware('Auto-connect Scale', 'R031'), findsOneWidget);
    expect(firmware('Dosing Scale', 'R031'), findsOneWidget);

    first.emitFirmware('stale');
    await tester.pump();

    expect(firmware('Auto-connect Scale', 'R031'), findsOneWidget);
    expect(firmware('Dosing Scale', 'R031'), findsOneWidget);
    expect(firmware('Auto-connect Scale', 'stale'), findsNothing);
    expect(firmware('Dosing Scale', 'stale'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    deviceController.dispose();
    discovery.dispose();
  });

  testWidgets('opens settings for an eligible plugin device', (tester) async {
    final discovery = MockDeviceDiscoveryService();
    final deviceController = DeviceController([discovery]);
    await deviceController.initialize();
    final settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();
    final device = _SettingsScale(deviceId: 'plugin:test.plugin:scale:one');
    discovery.addDevice(device);
    Uri? launched;

    await tester.pumpWidget(
      ShadApp(
        home: DeviceManagementPage(
          settingsController: settingsController,
          deviceController: deviceController,
          settingsLauncher: (uri) async {
            launched = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Device settings').first);
    expect(launched?.queryParameters['deviceId'], device.deviceId);
    expect(launched?.queryParameters['ui'], '1');

    await tester.pumpWidget(const SizedBox.shrink());
    deviceController.dispose();
    discovery.dispose();
  });

  testWidgets('shows a launch failure', (tester) async {
    final discovery = MockDeviceDiscoveryService();
    final deviceController = DeviceController([discovery]);
    await deviceController.initialize();
    final settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();
    discovery.addDevice(
      _SettingsScale(deviceId: 'plugin:test.plugin:scale:one'),
    );

    await tester.pumpWidget(
      ShadApp(
        home: ScaffoldMessenger(
          child: DeviceManagementPage(
            settingsController: settingsController,
            deviceController: deviceController,
            settingsLauncher: (_) async => false,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Device settings').first);
    await tester.pump();
    expect(find.text('Unable to open device settings.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    deviceController.dispose();
    discovery.dispose();
  });

  testWidgets('shows a URI construction failure', (tester) async {
    final discovery = MockDeviceDiscoveryService();
    final deviceController = DeviceController([discovery]);
    await deviceController.initialize();
    final settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();
    discovery.addDevice(
      _InvalidSettingsScale(deviceId: 'plugin:test.plugin:scale:one'),
    );

    await tester.pumpWidget(
      ShadApp(
        home: ScaffoldMessenger(
          child: DeviceManagementPage(
            settingsController: settingsController,
            deviceController: deviceController,
            settingsLauncher: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Device settings').first);
    await tester.pump();
    expect(find.text('Unable to open device settings.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    deviceController.dispose();
    discovery.dispose();
  });
}
