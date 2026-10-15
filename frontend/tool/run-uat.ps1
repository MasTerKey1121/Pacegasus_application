param(
    [Parameter(Mandatory = $true)][string]$DeviceId,
    [string]$Email = 'fortest.najajubjub@gmail.com',
    [string]$DisplayName = 'test account',
    [string]$ApiBaseUrl = '',
    [ValidateSet('register', 'existing', 'live')][string]$Mode = 'existing',
    [ValidateSet('manual', 'file')][string]$OtpMode = 'manual',
    [string]$Phase = 'profile',
    [string]$SecondaryEmail = 'pheeratchai.s@kkumail.com',
    [string]$ClubName = 'Pacegasus UAT',
    [string]$ShopListingId = ''
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
    if ($OtpMode -eq 'manual') { Write-Host 'กรอก OTP เองในแอปเมื่อถึงหน้ายืนยัน จากนั้นชุดทดสอบจะทำต่อ' }
    else { Write-Host "When waiting_otp appears, write the six-digit OTP to $otpPath using another terminal. Do not commit the OTP." }
    Push-Location $frontendPath
    try {
        $uatTarget = switch ($Mode) {
            'existing' { 'integration_test/uat_existing_account_test.dart' }
            'live' { 'integration_test/uat_live_test.dart' }
            default { 'integration_test/uat_registration_test.dart' }
        }
        $manualOtp = if ($OtpMode -eq 'manual') { 'true' } else { 'false' }
        $flutterArgs = @('test', $uatTarget, '-d', $DeviceId, '--reporter', 'expanded', "--dart-define=UAT_EMAIL=$Email", "--dart-define=UAT_NAME=$DisplayName", "--dart-define=UAT_MANUAL_OTP=$manualOtp", "--dart-define=UAT_PHASE=$Phase", "--dart-define=UAT_SECONDARY_EMAIL=$SecondaryEmail", "--dart-define=UAT_CLUB_NAME=$ClubName", "--dart-define=UAT_SHOP_LISTING=$ShopListingId")
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
