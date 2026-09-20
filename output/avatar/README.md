# Pacegasus avatar prototype

> Paused: the 3D viewer, wardrobe, and bundled model references have been removed
> from the Flutter app at the user's request. The Blender source is retained for
> later work. Preview commands and integration notes below describe the former
> prototype and are not currently available in the app.

Open `pacegasus_runner.blend` in Blender to edit the actual 3D model.
The source is reproducible with Blender 5.2:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/avatar/build_avatar.py
```

## Included

- Male runner prototype with closed smile, rounded eyes, sculpted nose and the supplied chest logo.
- Named editable groups: `Slot_Hair`, `Slot_Top`, `Slot_Bottom`, `Slot_Shoes`, `Slot_Stage`.
- Attachment points: `Socket_Back`, `Socket_Hand_L`, `Socket_Hand_R`.
- Four-second seamless idle, with planted feet and stationary stage.
- Two shirt colors and two independently selectable stages: track (black/gold concentric lane markings) and orbit (layered purple pedestal).
- Four bundled GLB combinations and transparent PNG fallback renders in `frontend/assets/models/`.
- Flutter Home and Wardrobe share account-scoped device-local selection. Motion respects reduced-animation settings.

## Preview

```powershell
cd frontend
flutter run -d chrome -t lib/avatar_preview.dart
```

This preview does not require login/backend access. Its saved choices are separate from signed-in users.
Android/iOS/web display real 3D; native desktop uses the matching still render.

## Deliberate prototype limits

This is a procedural, editable blockout inspired by the concept, not an exact sculpt of the generated image.
It uses rigid object hierarchy animation, not a skinned skeletal rig. There is no blinking or opening mouth yet.
Hair, shorts, shoes, wings and held items have no alternate catalog items yet.
Clothing and platform meshes are separate in Blender/GLB, but the app currently loads one of four pre-exported combinations.
Before a larger catalog, implement runtime slot assembly or material variants to avoid multiplying whole-character files.
The body needs additional work for exposed outfits; the prototype does not yet include fully modeled bare feet under shoes.
No backend inventory, purchases, or cloud sync are implemented.

## Validation

`flutter test test/avatar_provider_test.dart test/widget_test.dart` checks saved selection, restore races, write ordering, model slots/idle loop, navigation and shared wardrobe state.
Run on physical Android/iOS devices before release to verify WebView rendering, touch interaction, memory and frame rate.
