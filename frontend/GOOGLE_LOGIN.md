# Google login

Both Google buttons authenticate with Google, send the ID token to
`POST /api/auth/google`, and save the backend refresh token in secure storage.
The backend reuses an existing email account or creates a new verified account.
New accounts accept the app terms and complete onboarding before entering Home.
Canceling the Google picker or a rejected token does not create an app session.

## Android

Set `GOOGLE_CLIENT_ID` in `frontend/.env` to the same **Web application** OAuth
client ID as `GOOGLE_CLIENT_ID` in `backend/.env`. This is a public identifier;
never put the OAuth client secret in the app. The local frontend value was copied
from the backend configuration when this integration was added.

Register an Android OAuth client in the same Google Cloud project with
`com.example.pacegasus` and the SHA-1 of the certificate signing the installed app.
Add the Google account to test users if required by the consent configuration.

From `backend`, run `npm start`. From `frontend`, run `flutter run` on Android.
A full rebuild is required after adding this plugin. For a phone over USB, run
`adb reverse tcp:4000 tcp:4000`; for Wi-Fi, use
`flutter run --dart-define=API_BASE_URL=http://<computer-ip>:4000`.
The Android emulator can use the configured `10.0.2.2:4000` fallback.

Test both an existing account and a new account. A successful exchange returns
HTTP 200 with app access/refresh tokens. A new user should see terms and onboarding;
an existing user who completed onboarding should enter Home. Also test cancellation,
logout, and reopening the app.

## iOS

Requires an iOS OAuth client for the app Bundle ID. Set `GOOGLE_IOS_CLIENT_ID` in
`frontend/.env`, and add its reversed client ID as a URL scheme in
`ios/Runner/Info.plist` per the google_sign_in_ios documentation. This repository
does not yet have those iOS credentials. Windows desktop and the current web
frontend are outside this native Android integration.

Package setup: https://pub.dev/packages/google_sign_in
Android setup: https://pub.dev/packages/google_sign_in_android
iOS setup: https://pub.dev/packages/google_sign_in_ios
