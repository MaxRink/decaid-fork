import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/plugins/plugin_device_contract.dart';
import 'package:reaprime/src/settings/plugin_device_settings.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

typedef DeviceSettingsLauncher = Future<bool> Function(Uri uri);

class DeviceManagementPage extends StatefulWidget {
  const DeviceManagementPage({
    super.key,
    required this.settingsController,
    required this.deviceController,
    this.settingsLauncher,
  });

  static const routeName = '/devices';

  final SettingsController settingsController;
  final DeviceController deviceController;
  final DeviceSettingsLauncher? settingsLauncher;

  @override
  State<DeviceManagementPage> createState() => _DeviceManagementPageState();
}

class _DeviceManagementPageState extends State<DeviceManagementPage> {
  late StreamSubscription<List<Device>> _deviceSubscription;
  final List<StreamSubscription<DeviceInformation?>>
  _deviceInformationSubscriptions = [];
  late StreamSubscription<bool> _scanningSubscription;
  List<Device> _devices = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _devices = widget.deviceController.devices;
    _syncDeviceInformationSubscriptions();
    _scanning = widget.deviceController.isScanning;
    _deviceSubscription = widget.deviceController.deviceStream.listen((
      devices,
    ) {
      if (mounted) {
        setState(() => _devices = devices);
        _syncDeviceInformationSubscriptions();
      }
    });
    _scanningSubscription = widget.deviceController.scanningStream.listen((
      scanning,
    ) {
      if (mounted) {
        setState(() => _scanning = scanning);
      }
    });
    // A device that has never connected is not in the list, and the dosing
    // scale is chosen by hand rather than remembered on connect -- so without
    // a scan there would be nothing to choose from.
    if (_devices.isEmpty && !_scanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

  @override
  void dispose() {
    _deviceSubscription.cancel();
    for (final subscription in _deviceInformationSubscriptions) {
      subscription.cancel();
    }
    _scanningSubscription.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    try {
      // Discovery only: connecting here would hand a scale to brewing before
      // the user has said which one weighs the dose.
      await widget.deviceController.scanForDevices();
    } catch (_) {
      // A failed scan leaves whatever was already discovered in place.
    }
  }

  List<Device> get _machines =>
      _devices.where((d) => d.type == DeviceType.machine).toList();

  List<Device> get _scales =>
      _devices.where((d) => d.type == DeviceType.scale).toList();

  List<Device> get _sensors => _devices
      .where(
        (d) =>
            d.type == DeviceType.sensor &&
            d is DeviceSettingsCapable &&
            d.deviceSettings != null,
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: ListenableBuilder(
        listenable: widget.settingsController,
        builder: (context, _) {
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  _buildScanRow(),
                  _buildSection(
                    title: 'Auto-connect Machine',
                    icon: Icons.coffee_outlined,
                    devices: _machines,
                    selectedId: widget.settingsController.preferredMachineId,
                    emptyLabel: 'machines',
                    onSelected: (id) async {
                      await widget.settingsController.setPreferredMachineId(id);
                      if (mounted) _showSavedSnackbar();
                    },
                  ),
                  if (_sensors.isNotEmpty)
                    _buildSection(
                      title: 'Sensors',
                      icon: Icons.sensors_outlined,
                      devices: _sensors,
                      selectedId: null,
                      emptyLabel: 'sensors',
                      selectable: false,
                      onSelected: (_) async {},
                    ),
                  _buildSection(
                    title: 'Auto-connect Scale',
                    icon: Icons.scale_outlined,
                    devices: _scales
                        .where(
                          (d) =>
                              d.deviceId !=
                              widget.settingsController.dosingScaleId,
                        )
                        .toList(),
                    selectedId: widget.settingsController.preferredScaleId,
                    emptyLabel: 'scales',
                    onSelected: (id) async {
                      await widget.settingsController.setPreferredScaleId(id);
                      if (mounted) _showSavedSnackbar();
                    },
                  ),
                  // A second scale for weighing the dose. The one chosen here
                  // is never picked for brewing, which is what keeps the shot
                  // on the scale under the cup.
                  _buildSection(
                    title: 'Dosing Scale',
                    icon: Icons.balance_outlined,
                    devices: _scales
                        .where(
                          (d) =>
                              d.deviceId !=
                              widget.settingsController.preferredScaleId,
                        )
                        .toList(),
                    selectedId: widget.settingsController.dosingScaleId,
                    emptyLabel: 'scales',
                    onSelected: (id) async {
                      await widget.settingsController.setDosingScaleId(id);
                      if (mounted) _showSavedSnackbar();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildScanRow() {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _scanning
                  ? 'Scanning for devices…'
                  : _devices.isEmpty
                  ? 'No devices found yet. Scan to see what is nearby.'
                  : '${_devices.length} device(s) found',
              style: ShadTheme.of(context).textTheme.muted,
            ),
          ),
          const SizedBox(width: 12),
          ShadButton.outline(
            onPressed: _scanning ? null : _scan,
            leading: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching, size: 16),
            child: Text(_scanning ? 'Scanning' : 'Scan'),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Device> devices,
    required String? selectedId,
    required String emptyLabel,
    required Future<void> Function(String?) onSelected,
    bool selectable = true,
  }) {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (selectable)
            _buildDeviceRadio(
              name: 'None',
              subtitle: 'No auto-connect',
              isSelected: selectedId == null,
              onTap: () => onSelected(null),
            ),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No $emptyLabel currently known. Connect to devices first, then return here to set a preference.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            )
          else
            ...devices.map(
              (device) => _buildDeviceRadio(
                name: device.name,
                subtitle: _deviceSubtitle(device),
                isSelected: selectable && selectedId == device.deviceId,
                onTap: selectable ? () => onSelected(device.deviceId) : null,
                showSelection: selectable,
                trailing: _settingsButton(device),
              ),
            ),
        ],
      ),
    );
  }

  void _syncDeviceInformationSubscriptions() {
    for (final subscription in _deviceInformationSubscriptions) {
      subscription.cancel();
    }
    _deviceInformationSubscriptions.clear();
    for (final device in _devices.whereType<DeviceInformationCapable>()) {
      _deviceInformationSubscriptions.add(
        device.deviceInformation.skip(1).listen((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  String _deviceSubtitle(Device device) {
    final lines = <String>[_truncatedId(device.deviceId)];
    if (device case DeviceInformationCapable capable) {
      final firmwareVersion = capable.currentDeviceInformation?.firmwareVersion;
      if (firmwareVersion != null) {
        lines.add('Firmware: $firmwareVersion');
      }
      final batteryLevel = capable.currentDeviceInformation?.batteryLevel;
      if (batteryLevel != null) {
        lines.add('Battery: $batteryLevel% (device-reported)');
      }
      final powerSource = capable.currentDeviceInformation?.powerSource;
      if (powerSource == DevicePowerSource.usb) {
        lines.add('Power: USB (manual setting)');
      }
    }
    return lines.join(' · ');
  }

  Widget _buildDeviceRadio({
    required String name,
    required String subtitle,
    required bool isSelected,
    required VoidCallback? onTap,
    bool showSelection = true,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            if (showSelection)
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
              )
            else
              const Icon(Icons.sensors_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Future<void> _showScaleSettings(Device device) {
    return showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: widget.settingsController,
        builder: (context, _) => AlertDialog(
          title: Text('${device.name} settings'),
          content: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Powered by USB'),
            subtitle: const Text(
              'Enable when this Skale has external power. '
              'Battery reporting is suppressed while enabled.',
            ),
            value: widget.settingsController.isSkalePoweredByUsb(
              device.deviceId,
            ),
            onChanged: (value) => widget.settingsController
                .setSkalePoweredByUsb(device.deviceId, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _settingsButton(Device device) {
    final buttons = <Widget>[];
    if (device is UsbPowerConfigurable) {
      buttons.add(
        IconButton(
          tooltip: 'Configure ${device.name}',
          icon: const Icon(Icons.power),
          onPressed: () => _showScaleSettings(device),
        ),
      );
    }
    if (device is DeviceSettingsCapable && device.deviceSettings != null) {
      buttons.add(
        IconButton(
          tooltip: 'Device settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => _openDeviceSettings(device),
        ),
      );
    }
    if (buttons.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: buttons);
  }

  Future<void> _openDeviceSettings(Device device) async {
    if (!widget.deviceController.devices.any(
      (current) => identical(current, device),
    )) {
      _showSettingsError();
      return;
    }
    bool launched = false;
    try {
      final uri = pluginDeviceSettingsUriForDevice(
        device as DeviceSettingsCapable,
      );
      launched =
          await (widget.settingsLauncher?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.inAppBrowserView));
    } catch (_) {
      launched = false;
    }
    if (!mounted) return;
    if (!launched) _showSettingsError();
  }

  String _truncatedId(String id) {
    if (id.length > 8) {
      return 'ID: ...${id.substring(id.length - 8)}';
    }
    return 'ID: $id';
  }

  void _showSavedSnackbar() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Preference saved. Takes effect on next app start.'),
          duration: Duration(seconds: 3),
        ),
      );
  }

  void _showSettingsError() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Unable to open device settings.')),
      );
  }
}
