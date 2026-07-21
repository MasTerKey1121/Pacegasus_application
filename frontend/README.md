# Pacegasus (Flutter mock)

Flutter port of the Pacegasus mocks — **UI + local mock state only, not
connected to any backend yet**, as agreed. State is managed with
**Riverpod** (`flutter_riverpod`) using `ChangeNotifier`-based providers,
which is a good fit here: simple to read, easy to swap for real API calls
later, and doesn't require code generation.

## What's included

- **Auth (mock):** Login, Register — both just navigate into onboarding,
  no real auth check yet.
- **Onboarding (4 steps):** Basic info → Injury/conditions → Goal →
  Running history + summary → drops into the main app shell.
- **Main shell:** bottom nav with Home / Stats / Profile / Settings.
- **Home:** coin balance, Daily Wellness Check-in banner (unlocks daily
  missions once done), start-run CTA, quick link into the training
  schedule, "แผนวันนี้" lock card, week preview row.
- **Daily Wellness Check-in:** the 5 sliders from the mock, rewards coins
  on save.
- **Daily missions:** checklist with coin rewards.
- **Run session → summary → reward:** a timer simulates pace/distance
  (no GPS yet), then RPE / stress / mood / injury feedback, then a
  coin+EXP payout screen.
- **Training Schedule builder:** full port of the Intermediate 10K /
  Sub 1:40 phased plan (Base → Build → Peak → Taper → Race) we built as
  an HTML prototype — plan length picker, phase-aware weekly quotas,
  phase tabs, week navigator, tap-to-place day grid, the
  VO2Max/Tempo/Long-Run adjacency rule, and the locked Race-day /
  pre-race-rest cells.
- **Stats / Profile / Settings:** Stats and some Settings menu items are
  placeholders (no backend data yet); Profile shows the mock badges from
  the design.

All the "content" pieces (day names, session rules, copy) live in
`lib/models/` and `lib/providers/`, so swapping the mock state for real
API calls later should mostly mean rewriting the provider internals, not
the screens.

## Project structure

```
lib/
  app_theme.dart          colors, gradients, text styles, shared background
  main.dart                app entry point
  models/                  plain data classes (onboarding, wellness, training plan, ...)
  providers/                ChangeNotifier state for each feature
  widgets/common.dart       shared building blocks (buttons, cards, chips, sliders, toast)
  screens/
    auth/                  Login, Register
    onboarding/             4-step onboarding flow
    home/                   MainShell (bottom nav), Home, Daily missions
    wellness/               Daily Wellness Check-in
    run/                    Run session, summary, reward
    training/               Training Schedule builder
    stats/ profile/ settings/
```

## Running it

This sandbox doesn't have the Flutter SDK installed, so the code hasn't
been run through `flutter analyze` / `flutter run` — I read through every
file by hand to check types and syntax, but please run an analyze pass
before you trust it fully:

```bash
cd pacegasus
flutter create .        # generates the android/ios/etc platform folders
                         # (safe — it will not overwrite lib/ or pubspec.yaml)
flutter pub get
flutter analyze          # worth doing first, in case anything slipped through
flutter run
```

`flutter create .` is the important first step — this zip only has
`lib/` + `pubspec.yaml`, not the native Android/iOS project scaffolding,
since generating that reliably needs the actual Flutter tool.

## Notes / things you'll probably want to change first

- **Fonts:** using `google_fonts` (Kanit for headings, Sarabun for body)
  the way the HTML prototype did. It fetches fonts at runtime by default;
  call `GoogleFonts.config.allowRuntimeFetching = false` and bundle the
  `.ttf` files under `assets/fonts` if you need fully offline builds.
- **Logo:** no image asset was in the zip, so Login/Register use a
  stylised gold badge (`PacegasusLogo` in `widgets/common.dart`) instead
  of the real wing artwork — drop in the real PNG/SVG when you have it.
- **Run tracking:** `RunSessionNotifier` simulates distance at a fixed
  pace on a `Timer` — swap this for real GPS (e.g. `geolocator`) later.
- **Everything resets on app restart** — there's no local persistence
  (`shared_preferences`/hive/etc.) yet since we said mock-only for now.
