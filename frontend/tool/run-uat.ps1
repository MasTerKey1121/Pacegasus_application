param(
    [Parameter(Mandatory = $true)][string]$DeviceId,
    [string]$Email = 'fortest.najajubjub@gmail.com',
    [string]$DisplayName = 'test account',
    [string]$ApiBaseUrl = '',
    [ValidateSet('register', 'existing')][string]$Mode = 'existing'
)
$ErrorActionPreference = 'Stop'
$frontendPath = Split-Path -Parent $PSScriptRoot
$runtimePath = Join-Path $frontendPath '.uat-runtime'
$runStamp = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(7)).ToString('yyyy-MM-dd_HHmmss', [Globalization.CultureInfo]::InvariantCulture)
$outputPath = Join-Path (Split-Path -Parent $frontendPath) "output\uat\automated\$runStamp"
New-Item -ItemType Directory -Path $runtimePath,$outputPath -Force | Out-Null
$otpPath = Join-Path $runtimePath 'otp.txt'
if (Test-Path -LiteralPath $otpPath) { Remove-Item -LiteralPath $otpPath }
$bridgePath = Join-Path $PSScriptRoot 'uat_bridge.cjs'
$nodePath = (Get-Command node.exe).Source
$bridgeArgs = @('"' + $bridgePath + '"', '"' + $runtimePath + '"', '"' + $outputPath + '"', '8765')
$bridgeProcess = Start-Process -FilePath $nodePath -ArgumentList $bridgeArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtimePath 'bridge.log') -RedirectStandardError (Join-Path $runtimePath 'bridge-error.log')
$exitCode = 1
try {
    $ready = $false
    for ($i = 0; $i -lt 20; $i++) {
        if ($bridgeProcess.HasExited) { throw 'UAT bridge could not start; inspect .uat-runtime/bridge-error.log' }
        try { Invoke-RestMethod -Uri 'http://127.0.0.1:8765/status' | Out-Null; $ready = $true; break } catch { Start-Sleep -Milliseconds 200 }
    }
    if (!$ready) { throw 'UAT bridge did not become ready' }
    & adb -s $DeviceId reverse tcp:8765 tcp:8765
    if ($LASTEXITCODE -ne 0) { throw 'Could not connect Android to UAT bridge' }
    Write-Host "Evidence folder: $outputPath"
    Write-Host "When waiting_otp appears, write the six-digit OTP to $otpPath using another terminal. Do not commit the OTP."
    Push-Location $frontendPath
    try {
        $uatTarget = if ($Mode -eq 'existing') { 'integration_test/uat_existing_account_test.dart' } else { 'integration_test/uat_registration_test.dart' }
        $flutterArgs = @('test', $uatTarget, '-d', $DeviceId, '--reporter', 'expanded', "--dart-define=UAT_EMAIL=$Email", "--dart-define=UAT_NAME=$DisplayName")
        if ($ApiBaseUrl) { $flutterArgs += "--dart-define=API_BASE_URL=$ApiBaseUrl" }
        & flutter @flutterArgs
        $exitCode = $LASTEXITCODE
    } finally { Pop-Location }
} finally {
    if (Test-Path -LiteralPath $otpPath) { Remove-Item -LiteralPath $otpPath }
    if (!$bridgeProcess.HasExited) { Stop-Process -Id $bridgeProcess.Id }
    & adb -s $DeviceId reverse --remove tcp:8765
}
exit $exitCode
