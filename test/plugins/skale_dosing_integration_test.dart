import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/dosing_scale_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/plugins/plugin_ble_registry.dart';
import 'package:reaprime/src/plugins/plugin_manager.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_device_scanner.dart';
import '../helpers/mock_settings_service.dart';
import '../helpers/skale_plugin_fixture.dart';
import 'plugin_test_helpers.dart';

final _settings = SkaleSettingsFixture();

void main() {
  setUpAll(_settings.start);
  setUp(() {
    _settings.values.clear();
    _settings.defaultUsbPower = false;
    _settings.defaultSquareAction = false;
    _settings.error = false;
    _settings.delay = Duration.zero;
    _settings.machineDelay = Duration.zero;
    _settings.scaleConnections = {'brewing': null, 'dosing': null};
    _settings.machineState = {
      'deviceId': 'MockDe1',
      'connectionGeneration': 1,
      'state': {'state': 'idle', 'substate': 'idle'},
    };
    _settings.machineInfo = {
      'version': '1.0',
      'model': 'MockDe1',
      'serialNumber': 'mock',
      'GHC': false,
    };
    _settings.machineRequests.clear();
    HttpOverrides.global = SkaleSettingsHttpOverrides(_settings);
  });
  tearDown(() => HttpOverrides.global = null);
  tearDownAll(_settings.close);
  _registerTests();
}

void _registerTests() {
  test(
    'routes two same-plugin scales to brewing and dosing independently',
    () async {
      final pluginManager = PluginManager(kvStore: FakeKeyValueStoreService());
      final scanner = MockDeviceScanner();
      final discovery = MockDeviceDiscoveryService();
      final de1 = MockDe1Controller(controller: DeviceController([discovery]));
      final settingsService = MockSettingsService();
      final settingsController = SettingsController(settingsService);
      await settingsController.loadSettings();
      final brewingController = ScaleController();
      final dosingController = DosingScaleController();
      final connectionManager = ConnectionManager(
        deviceScanner: scanner,
        de1Controller: de1,
        scaleController: brewingController,
        dosingScaleController: dosingController,
        settingsController: settingsController,
        connectTimeout: const Duration(seconds: 5),
      );
      addTearDown(() async {
        await dosingController.disconnect();
        await connectionManager.dispose();
        await pluginManager.dispose();
        scanner.dispose();
        discovery.dispose();
      });
      await loadSkalePlugin(pluginManager);

      final evidence = BleAdvertisementEvidence(
        name: 'Skale2',
        serviceUuids: ['ff08'],
      );
      final driver = pluginManager.bleService.registry
          .decide(evidence)
          .drivers
          .single;
      final brewingTransports = <SkalePluginTransport>[];
      final dosingTransports = <SkalePluginTransport>[];

      Future<Scale> candidate(
        String physicalId,
        List<SkalePluginTransport> transports,
      ) async {
        return await pluginManager.bleService.createCandidate(
              driver: driver,
              physicalId: physicalId,
              evidence: evidence,
              admit: () => true,
              createTransport: () {
                final transport = SkalePluginTransport(
                  physicalId,
                  batteryPresent: false,
                );
                transports.add(transport);
                return transport;
              },
            )
            as Scale;
      }

      final brewingScale = await candidate('AA:01', brewingTransports);
      final dosingScale = await candidate('AA:02', dosingTransports);
      await settingsController.setDosingScaleId(dosingScale.deviceId);
      scanner.addDevice(brewingScale);
      scanner.addDevice(dosingScale);
      final brewingSnapshots = <WeightSnapshot>[];
      final dosingSnapshots = <ScaleSnapshot>[];
      final brewingSnapshotSubscription = brewingController.weightSnapshot
          .listen(brewingSnapshots.add);
      final dosingSnapshotSubscription = dosingController.snapshot.listen(
        dosingSnapshots.add,
      );
      addTearDown(brewingSnapshotSubscription.cancel);
      addTearDown(dosingSnapshotSubscription.cancel);

      final scan = connectionManager.scanAndConnect();
      final brewingTransport = await _waitForTransport(brewingTransports);
      await brewingTransport.buttonSubscribed.future.timeout(
        const Duration(seconds: 5),
      );
      await brewingTransport.finalEnable.future.timeout(
        const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      brewingTransport.emitWeight(skaleFourBytePacket(12));

      final dosingTransport = await _waitForTransport(dosingTransports);
      await dosingTransport.buttonSubscribed.future.timeout(
        const Duration(seconds: 5),
      );
      await dosingTransport.finalEnable.future.timeout(
        const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      dosingTransport.emitWeight(skaleFourBytePacket(34));
      await scan.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(brewingController.lastConnectedDeviceId, brewingScale.deviceId);
      expect(dosingController.lastConnectedDeviceId, dosingScale.deviceId);
      expect(brewingSnapshots.last.weight, closeTo(12, 0.001));
      expect(dosingSnapshots.last.weight, closeTo(34, 0.001));
      expect(pluginManager.bleService.registry.activeBindingCount, 2);

      final brewingWritesBeforeTare = brewingTransport.writes.length;
      final dosingWritesBeforeTare = dosingTransport.writes.length;
      await brewingController.tare();
      await dosingController.tare();
      expect(
        brewingTransport.writes
            .skip(brewingWritesBeforeTare)
            .map((write) => write.data.toList()),
        [
          [0x10],
        ],
      );
      expect(
        dosingTransport.writes
            .skip(dosingWritesBeforeTare)
            .map((write) => write.data.toList()),
        [
          [0x10],
        ],
      );

      await dosingController.disconnect();
      expect(
        brewingController.currentConnectionState,
        ConnectionState.connected,
      );
      brewingTransport.emitWeight(skaleFourBytePacket(56));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(brewingSnapshots.last.weight, closeTo(56, 0.001));
      expect(
        dosingController.currentConnectionState,
        ConnectionState.disconnected,
      );

      final reconnect = dosingController.connectToScale(dosingScale);
      final reconnectTransport = await _waitForTransport(
        dosingTransports,
        count: 2,
      );
      await reconnectTransport.buttonSubscribed.future.timeout(
        const Duration(seconds: 5),
      );
      await reconnectTransport.finalEnable.future.timeout(
        const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      reconnectTransport.emitWeight(skaleFourBytePacket(78));
      await reconnect.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        brewingController.currentConnectionState,
        ConnectionState.connected,
      );
      expect(
        dosingController.currentConnectionState,
        ConnectionState.connected,
      );
      expect(dosingSnapshots.last.weight, closeTo(78, 0.001));
    },
  );

  test('dosing-only scan leaves brewing unconnected', () async {
    final pluginManager = PluginManager(kvStore: FakeKeyValueStoreService());
    final scanner = MockDeviceScanner();
    final discovery = MockDeviceDiscoveryService();
    final de1 = MockDe1Controller(controller: DeviceController([discovery]));
    final settingsService = MockSettingsService();
    final settingsController = SettingsController(settingsService);
    await settingsController.loadSettings();
    final brewingController = ScaleController();
    final dosingController = DosingScaleController();
    final connectionManager = ConnectionManager(
      deviceScanner: scanner,
      de1Controller: de1,
      scaleController: brewingController,
      dosingScaleController: dosingController,
      settingsController: settingsController,
      connectTimeout: const Duration(seconds: 5),
    );
    addTearDown(() async {
      await dosingController.disconnect();
      await connectionManager.dispose();
      await pluginManager.dispose();
      scanner.dispose();
      discovery.dispose();
    });
    await loadSkalePlugin(pluginManager);

    final evidence = BleAdvertisementEvidence(serviceUuids: ['ff08']);
    final driver = pluginManager.bleService.registry
        .decide(evidence)
        .drivers
        .single;
    final transports = <SkalePluginTransport>[];
    final dosingScale =
        await pluginManager.bleService.createCandidate(
              driver: driver,
              physicalId: 'AA:03',
              evidence: evidence,
              admit: () => true,
              createTransport: () {
                final transport = SkalePluginTransport(
                  'AA:03',
                  batteryPresent: false,
                );
                transports.add(transport);
                return transport;
              },
            )
            as Scale;
    await settingsController.setDosingScaleId(dosingScale.deviceId);
    scanner.addDevice(dosingScale);

    final scan = connectionManager.scanAndConnect();
    final transport = await _waitForTransport(transports);
    await transport.buttonSubscribed.future.timeout(const Duration(seconds: 5));
    await transport.finalEnable.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    transport.emitWeight(skaleFourBytePacket(9));
    await scan.timeout(const Duration(seconds: 5));

    expect(
      brewingController.currentConnectionState,
      isNot(ConnectionState.connected),
    );
    expect(dosingController.lastConnectedDeviceId, dosingScale.deviceId);
    expect(pluginManager.bleService.registry.activeBindingCount, 1);
  });
}

Future<SkalePluginTransport> _waitForTransport(
  List<SkalePluginTransport> transports, {
  int count = 1,
}) async {
  for (var attempt = 0; attempt < 100 && transports.length < count; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(transports.length, greaterThanOrEqualTo(count));
  return transports[count - 1];
}
