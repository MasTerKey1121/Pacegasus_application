# Let a USB-connected Android device reach the backend running on this PC.
# The command is deliberately optional: Windows, web, or an unavailable adb
# installation must never prevent Flutter from launching.
$ErrorActionPreference = 'SilentlyContinue'

$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($null -eq $adbCommand) {
  Write-Host 'No Android device connection prepared (adb was not found).'
  exit 0
}

$connectedDevices = & $adbCommand.Source devices |
  Select-Object -Skip 1 |
  Where-Object { $_ -match '^([^\s]+)\s+device$' } |
  ForEach-Object { $Matches[1] }

if ($connectedDevices.Count -eq 0) {
  Write-Host 'No Android device connected; Flutter will use the selected available device.'
  exit 0
}

foreach ($serial in $connectedDevices) {
  & $adbCommand.Source -s $serial reverse tcp:4000 tcp:4000 | Out-Null
  Write-Host "Android API connection prepared for $serial."
}

exit 0
