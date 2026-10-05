$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

foreach ($platform in @('ios', 'macos')) {
    $path = Join-Path $root "$platform/Runner/Info.plist"
    $plist = [xml](Get-Content -LiteralPath $path -Raw)
    foreach ($key in @('NSCameraUsageDescription', 'NSMicrophoneUsageDescription')) {
        $description = $plist.SelectSingleNode("/plist/dict/key[text()='$key']/following-sibling::*[1][self::string]")
        if ($null -eq $description -or [string]::IsNullOrWhiteSpace($description.InnerText)) {
            throw "$platform native capture requires a nonempty $key to avoid a TCC privacy kill"
        }
        Write-Output "PASS: $platform $key"
    }
}

foreach ($configuration in @('DebugProfile', 'Release')) {
    $path = Join-Path $root "macos/Runner/$configuration.entitlements"
    $entitlements = [xml](Get-Content -LiteralPath $path -Raw)
    if ($null -ne $entitlements.SelectSingleNode("/plist/dict/key[text()='com.apple.security.device.audio-input']")) {
        throw "$configuration must not enable macOS microphone access"
    }
    Write-Output "PASS: $configuration has no audio-input entitlement"
}
