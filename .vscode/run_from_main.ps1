# Entry point for VS Code's "Run Code" button while lib/main.dart is open.
# It starts a local API only when port 4000 is unused, then keeps Flutter in
# the foreground so the usual hot reload and device selection still work.
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$prepareScript = Join-Path $PSScriptRoot 'prepare_mobile_api.ps1'
& $prepareScript

$apiWasAlreadyRunning = $false
try {
  $apiWasAlreadyRunning = $null -ne (Get-NetTCPConnection -LocalPort 4000 -State Listen -ErrorAction Stop)
} catch {
  # No process is listening on port 4000 yet.
}

$apiProcess = $null
if (-not $apiWasAlreadyRunning) {
  $apiProcess = Start-Process `
    -FilePath 'node' `
    -ArgumentList 'src/server.js' `
    -WorkingDirectory (Join-Path $projectRoot 'backend') `
    -WindowStyle Hidden `
    -PassThru
  Start-Sleep -Seconds 1
}

try {
  Push-Location (Join-Path $projectRoot 'frontend')
  & flutter run --dart-define=API_BASE_URL=http://localhost:4000
} finally {
  Pop-Location
  if ($null -ne $apiProcess -and -not $apiProcess.HasExited) {
    Stop-Process -Id $apiProcess.Id -ErrorAction SilentlyContinue
  }
}
