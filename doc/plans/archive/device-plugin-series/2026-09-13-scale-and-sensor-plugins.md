# Scale and sensor plugins

This document records the lasting ownership model for plugin scales and
sensors. It describes the design shipped by the device plugin series, rather
than a temporary implementation sequence.

## Ownership boundaries

JavaScript owns protocol parsing, encoding, readiness, protocol timers,
validated device values, and plugin commands. Dart owns discovery, physical
transport, permissions, connection ownership, quotas, teardown, reconnect, and
publication enforcement. A plugin instance is independent for every physical
device: timers, subscriptions, pending requests, session state, settings, and
published values are never keyed only by driver or model.

BLE bindings carry a generation and an opaque domain `connectionId`. The ID is
an identity for source checks and stale-context rejection; it is never a GATT
authority. Retiring a binding clears its session publications and cancels only
that binding's work. A replacement binding receives a new generation, and old
JavaScript contexts cannot publish into it.

## Scale metadata

Firmware revision and battery level are connected-session metadata. `PluginScale`
publishes only the opaque `firmwareVersion` string and a nullable battery value
validated as an integer from 0 through 100. The narrow
`DeviceInformationCapable` capability is shared with native scales, and the
REST handler projects that capability through `/api/v1/scale/info`. Metadata is
kept out of discovery inventory and does not establish first-weight readiness.

Metadata is cleared on connection failure, disconnect, revocation, replacement,
and disposal. Publication is fenced by the current session, so a delayed read
or stale JavaScript context cannot restore an old value. Firmware and battery
are optional: an unavailable value clears that field without failing the
connection.

## Roles and commands

The brewing and dosing scale roles have separate ownership and publication.
The configured dosing identity is excluded from brewing selection, and the
Bengle integrated-scale ownership and external-dosing exclusion remain intact.
Circle tares only the originating assigned role. Square is a brewing action;
it is a no-op for dosing. Queued machine writes check machine identity,
generation, state, gateway-control status, source role, public device ID, and
source generation at dispatch and immediately before the write. A sleeping
machine is never woken by this path.

## Per-device settings

A plugin can declare a driver `settingsEndpoint` naming one of its declared HTTP
endpoints. The host validates the manifest and `api` permission, then the native
Device Management page opens the plugin-owned URL with `ui=1`, the exact public
`deviceId`, and `deviceName`. The page uses `url_launcher` with
`LaunchMode.inAppBrowserView`. The plugin endpoint remains the authority for
validation and persistence; the host does not create a second settings schema
or store.

## Sensor integration

E64 sensors use the host-owned WebSocket transport and the same per-instance
session rules. Each instance has independent request IDs, pending maps, timers,
epochs, and settings. The initial contract is read-only and publishes the
declared typed object channel. Unknown commands, malformed entries, duplicate
IDs, and invalid connection parameters are rejected before transport use.
Sensor selection follows the declared sensor contract, so an attached milk
probe or a second E64 cannot change an unrelated steam recording by map order.

## Verification contract

The behavior matrix covers zero, one, and two same-model instances; distinct
physical identities; concurrent connections; per-instance metadata, commands,
and settings; reconnect, teardown, revocation, stale callbacks, and quotas;
brewing and dosing role routing; and two E64 sensors alongside scales and a
milk probe. Native and plugin metadata selection are tested together to ensure
one instance cannot leak into another or into inventory.
