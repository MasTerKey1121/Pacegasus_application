# Automated UAT with screenshots

This suite uses Flutter Integration Test to interact with the real app and its
configured API. It is intentionally a separate command from ordinary unit tests
because registration and wellness write real account data and require an emailed
OTP. It never deletes an account or bypasses authentication.

## Run on Android

Requirements: Flutter, Node.js, Android platform-tools (`adb`), an unlocked
connected Android phone/emulator, and access to the chosen email inbox.
Start with the app logged out and an email eligible for registration.

From `frontend/`:

```powershell
flutter pub get
flutter devices
.\tool\run-uat.ps1 -DeviceId R5CRC0T396T
```

Defaults: `pasen680@gmail.com`, display name `test account`, and the API configured
in the app. Override with `-Email`, `-DisplayName`, or `-ApiBaseUrl` if required.
The code defaults to a deployed API; local backend fixes need that deployment
updated or `-ApiBaseUrl` pointing to the appropriate test server.

When `.uat-runtime/bridge.log` shows `STATE waiting_otp`, enter the current
six-digit code in a second PowerShell terminal:

```powershell
Set-Content -LiteralPath .uat-runtime/otp.txt -Value '<six-digit-code>' -NoNewline
```

Replace the placeholder with the actual code. If running through this chat,
send the code here and the assistant can write it to that local runtime file.
The local bridge binds to loopback only, consumes the code once, and does not
include it in logs, screenshots or reports. The ignored runtime directory keeps
the input out of Git. Supply OTP within four minutes; otherwise rerun for a new
code. Do not reuse an old code.

## Assertions and evidence

The test checks Login, Register inputs, consent disabled/enabled states,
registration OTP purpose, successful authentication, four onboarding steps,
onboarding completion on Home, wellness validation and saving, and Profile name
and public UID with no retry error. No service/provider mocks are installed.

Synthetic onboarding data: birth date 1995-01-01, male, 65 kg, 170 cm, three
running days/week, no chronic conditions or injuries, 5K goal without a finish
time, no previous running experience. These are test values, not the user's
personal health information.

Each asserted checkpoint immediately saves a PNG and updates `results.json` and
`UAT-REPORT.md` in a dated run folder under `output/uat/automated/`. Failures are
recorded as failed, with a separate failure screenshot when possible. Later steps
are not marked passed. Screenshot capture/upload failure also fails the suite.
Saved screenshots contain the chosen email and account details; review them
before sharing. Android screenshots cover Flutter-rendered content; native
WebView/3D output is not a visual acceptance assertion.

The suite does not cover purchases, friend/club actions, a training-plan
registration, run/GPS, every subpage, or all visual layouts. Expand it with
explicit assertions and checkpoint captures for further user journeys. The
user's final product acceptance remains separate from automated test results.

## Existing-account health-only flow (current default)

The runner now defaults to `-Mode existing` and `fortest.najajubjub@gmail.com`.
It executes `integration_test/uat_existing_account_test.dart`. It uses an existing
session if present or requests a login OTP. An incomplete account follows all four
onboarding pages with only `เพิ่มความอึด` selected; distance goal must remain null.
Completed accounts go straight to Home. Already-completed daily wellness is
checked as restored instead of submitted again. Those conditional checkpoints
are explicitly labeled in the report. Use `-Mode register` for the original
new-registration scenario. The account must already exist for existing mode.
Running-history fixture: choose ไม่เคย and น้อยกว่า 5 km; both are required before Start is enabled.
