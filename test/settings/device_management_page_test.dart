import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/settings/device_management_page.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_settings_service.dart';
import '../helpers/test_scale.dart';

class _ButtonScale extends TestScale implements ScaleButtonCapable {
  _ButtonScale() : super(name: 'Skale2');

  @override
  Stream<ScaleButton> get buttonPresses => const Stream.empty();
}

void main() {
  testWidgets('scale button switch is off by default and persists changes', (
    tester,
  ) async {
    final settings = SettingsController(MockSettingsService());
    await settings.loadSettings();
    final discovery = MockDeviceDiscoveryService();
    final devices = DeviceController([discovery]);
    await devices.initialize();
    discovery.addDevice(_ButtonScale());

    await tester.pumpWidget(
      ShadApp(
        builder: (_, child) => ScaffoldMessenger(child: child!),
        home: Scaffold(
          body: DeviceManagementPage(
            settingsController: settings,
            deviceController: devices,
          ),
        ),
      ),
    );

    expect(settings.scaleButtonStartsEspresso, isFalse);
    expect(find.text('Square button starts espresso'), findsNothing);
    await tester.tap(find.byTooltip('Configure Skale2'));
    await tester.pumpAndSettle();

    expect(find.text('Skale2 settings'), findsOneWidget);
    final toggle = find.widgetWithText(
      SwitchListTile,
      'Square button starts espresso',
    );
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(settings.scaleButtonStartsEspresso, isTrue);

    devices.dispose();
    discovery.dispose();
    settings.dispose();
  });
}
