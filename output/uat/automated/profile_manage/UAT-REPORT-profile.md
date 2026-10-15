# Automated UAT — Pacegasus

Status: **passed**

Phase profile completed: only listed assertions passed. Other UAT cases remain Not Run.

Tests run through Flutter Integration Test against the configured real API.
Guided phase profile. Human operates real UI (including OTP); automatic API/state assertions and screenshots. Only checkpoint assertions are checked. Negative cases and other parts of the 88-case plan remain Not Run. No account deletion.

Screenshots support only the stated assertions. A completed phase does not mean all 88 UAT cases passed.

| Step | Result | Evidence |
| --- | --- | --- |
| Profile loads original account and Copy places exact public UID in clipboard | passed | ผลตรวจตามรายงาน |
| Whitespace-only name is rejected and stored name remains unchanged | passed | [profile-empty-rejected](screenshots/profile-empty-rejected.png) |
| Changed profile name persists in real API and visible UI; UID unchanged (partial UAT-04-002) | passed | [profile-name](screenshots/profile-name.png) |
| Home displays new saved name; screenshot waits three seconds for model | passed | [profile-home-name](screenshots/profile-home-name.png) |
| Reopening Profile reloads the edited name from the real server | passed | ผลตรวจตามรายงาน |
| Original display name restored via UI and verified in server; no logout or deletion | passed | [profile-original-name-restored](screenshots/profile-original-name-restored.png) |

## Screenshots

### Whitespace-only name is rejected and stored name remains unchanged

![profile-empty-rejected](screenshots/profile-empty-rejected.png)

### Changed profile name persists in real API and visible UI; UID unchanged (partial UAT-04-002)

![profile-name](screenshots/profile-name.png)

### Home displays new saved name; screenshot waits three seconds for model

![profile-home-name](screenshots/profile-home-name.png)

### Original display name restored via UI and verified in server; no logout or deletion

![profile-original-name-restored](screenshots/profile-original-name-restored.png)
