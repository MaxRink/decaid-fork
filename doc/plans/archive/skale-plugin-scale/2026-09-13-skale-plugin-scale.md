# Skale plugin scale — design rationale

This is the Skale-specific archive selected from `design-rationale.md`. It records the decisions that make two same-model Skale devices safe to use at once.

## Ownership and identity

Dart owns discovery, physical I/O, permissions, binding lifetime, teardown, reconnect, quotas, and host routing. JavaScript owns protocol parsing, per-instance timers and callbacks, plugin settings, and device button policy. Every physical Skale is a distinct public instance: mutable state, settings, metadata, callbacks, request IDs, and connection epochs are keyed by its stable identity, never only by model or driver. The host bound is four active plugin bindings; existing global device, transport, and resource quotas remain in force.

Plugin scale information is session-scoped. A retired session loses publication authority before its replacement can publish, and stale callbacks are fenced per binding. `PluginProtocolDevice.connectionId` identifies the active plugin connection and does not replace the physical identity or add USB provenance. Teardown keeps ownership and reservations until native teardown is confirmed.

## Settings authority

USB power is an explicit default-off per-device setting. It is persisted through the plugin KV authority under the stable public device identity, with plugin-global settings kept separate. Native settings UI, when present, must use that same endpoint and validate it against the loaded manifest and API permission rather than infer a URL or introduce another store.

## Button safety

A circle press tares only the currently assigned originating role. The dosing square is ignored. The brewing square is a guarded transition: inactive-GHC idle may request espresso, while active espresso may request idle. Sleeping, unknown or missing machine state, active or unknown GHC for start, stale source identity, replacement generation, and full-gateway start conditions are safe no-ops or rejections. Stop uses the direct path and may proceed through a full gateway. A stop advances the shared cancellation epoch so an older queued start cannot issue an espresso request after the stop.

## Verification and limits

The deterministic fixture uses two same-plugin Skales with distinct physical IDs, independent sessions, role selection, per-instance tare, disconnect/reconnect, and scan coverage. The actual-host integration routes button requests through `De1Handler` and `ScaleHandler` and waits on the completed scale-connections response before asserting that dosing produced no machine request. The captured environment has no real Skale hardware; hardware validation remains a maintainer gate.
