param(
    [ValidateSet('register-primary','setup-secondary','program','run','run-review','profile','primary-social','secondary-social','approve-club','verify-secondary','shop')]
    [string]$Phase = 'register-primary',
    [string]$DeviceId = '',
    [string]$ApiBaseUrl = '',
    [string]$ClubName = 'Pacegasus UAT',
    [string]$ShopListingId = '',
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
$frontendPath = Split-Path -Parent $PSScriptRoot
$repoPath = Split-Path -Parent $frontendPath
$mainEmail = 'fortest.najajubjub@gmail.com'
$secondaryEmail = 'pheeratchai.s@kkumail.com'
$planPath = Join-Path $repoPath 'docs\uat\Pacegasus-UAT-Test-Cases.md'
$caseIds = [regex]::Matches((Get-Content -LiteralPath $planPath -Raw -Encoding UTF8), '(?m)^\| (UAT-\d{2}-\d{3}) \|') | ForEach-Object { $_.Groups[1].Value }
$runtimePath = Join-Path $frontendPath '.uat-runtime'
New-Item -ItemType Directory -Path $runtimePath -Force | Out-Null
$plan = [ordered]@{
    preparedAt = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(7)).ToString('o')
    primaryEmail = $mainEmail; secondaryEmail = $secondaryEmail
    otpEntry = 'human-in-app'; phase = $Phase
    apiBaseUrl = $ApiBaseUrl; deviceId = $DeviceId
    executionRequested = [bool]$Execute
    cases = @($caseIds | ForEach-Object { @{ id = $_; status = 'Not Run' } })
}
$plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runtimePath 'prepared-plan.json') -Encoding UTF8
Write-Host "Prepared $($caseIds.Count) UAT cases. Phase: $Phase"
Write-Host "Main: $mainEmail; Secondary: $secondaryEmail; OTP: enter directly in app"
if (!$Execute) {
    Write-Host 'Preparation only. No app, device, API or email was contacted. Add -Execute only when ready to run.'
    return
}
if (!$DeviceId -or !$ApiBaseUrl) { throw 'Execution requires explicit -DeviceId and -ApiBaseUrl.' }
if ($ApiBaseUrl -notmatch '^https?://') { throw 'ApiBaseUrl must start with http:// or https://' }
if ($Phase -eq 'shop' -and !$ShopListingId) { throw 'Choose a specific -ShopListingId before a real purchase.' }
$secondaryPhase = $Phase -in @('setup-secondary','secondary-social','verify-secondary')
$email = if ($secondaryPhase) { $secondaryEmail } else { $mainEmail }
$mode = if ($Phase -eq 'register-primary') { 'register' } else { 'live' }
& (Join-Path $PSScriptRoot 'run-uat.ps1') -DeviceId $DeviceId -Email $email -DisplayName 'test account' -ApiBaseUrl $ApiBaseUrl -Mode $mode -OtpMode manual -Phase $Phase -SecondaryEmail $secondaryEmail -ClubName $ClubName -ShopListingId $ShopListingId
exit $LASTEXITCODE
