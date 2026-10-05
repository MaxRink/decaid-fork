# Apple Native Video Capture Privacy

## Cause

PR #939's iPhone crash report confirms a TCC privacy kill. WKWebView's native
video file-input picker configures an audio input, but the app has no
`NSMicrophoneUsageDescription`. This picker bypasses the Dart live-camera gate.
The pinned macOS plugin uses NSOpenPanel for file inputs; the report does not
establish a macOS crash from the same interaction.

## Decision

Add microphone usage descriptions to both Apple app plists. A usage description
does not grant permission. iOS can ask for microphone permission when a user
chooses native video recording, and the recording can include audio after that
permission is granted. Keep live WebView microphone and combined requests
denied. Leave onboarding, permission-handler opt-ins and macOS audio-input
entitlements unchanged.

The user approved this tradeoff after considering camera-only native recording.
The pinned plugin cannot configure Apple's file-input recorder without audio.
Page-script restrictions would not provide a native permission boundary and
could restrict file imports.

## Verification

On Windows with Flutter 3.47.5 / Dart 3.13.4, the XML-based regression check
failed on the missing iOS microphone usage description before the fix. After
the fix, all six declaration and entitlement checks passed. The focused camera
suite passed 77 tests with zero error events and empty stderr. Formatting
checked 906 Dart files with zero changes; analysis reported no issues. The
dependency lockfile stayed unchanged. Test assets use the pinned external
plugins and the CI-style bundled-skin stub.

The full Flutter suite did not run: an existing Windows Decaid Test session
held the lab lock and ports 3000, 4001 and 8080. No approval to interrupt that
session was given. No Apple build or hardware verification was performed on
this Windows host. Apple hardware must verify native recording, microphone
denial and cancellation, and continued live-microphone denial. The manual audit
checklist includes these cases.
