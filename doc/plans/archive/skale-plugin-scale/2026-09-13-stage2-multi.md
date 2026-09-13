# Skale plugin scale — stage 2 rationale

Stage 2 extends the frozen single-device Skale driver to two concurrent
instances. The host quota and the dosing controller are generic dependencies;
the plugin remains responsible for protocol state, per-device settings, and
button policy inside each `create()` result.

The read-only scale connection projection carries independent brewing and
dosing identities. Circle presses tare the assigned instance. Square presses
remain a brewing-only guarded machine action, so a dosing scale can never
start or stop the machine. Guarded requests retain the captured machine and
scale session tokens and are revalidated by the host at dispatch.

The two roles use separate controllers and settings identities. Disconnecting
or reconnecting the dosing scale leaves brewing snapshots and actions alive,
and stale plugin sessions cannot publish or act for their replacements.
