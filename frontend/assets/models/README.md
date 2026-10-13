# Home avatar

`pacegasus_wave_male_v8.glb` is the v8 runner (about 1.89 MB), with
`Wave_Greeting` retargeted from the user-supplied Waving.fbx and `Idle_Loop`.
The clothing and hair remain separate meshes; outfit customization is not
implemented in the app in this change.

HomeAvatar subscribes to the app's PageRoute observer. The model is recreated
on initial Home display and after another page pops back to Home. Each new
viewer waits for the model's load event, plays Wave_Greeting once, then uses
the finished event to switch to repeating Idle_Loop. Normal Home rebuilds,
drawers, and dialogs do not restart the greeting. Leaving Home disposes the
viewer so it is not animating behind another page. Returning currently
recreates the viewer (a simple prototype, rather than a persistent GPU cache).

Rendering is supported on Android/iOS through model_viewer_plus and on web
through the bundled model-viewer component. Windows/macOS/Linux native builds
show an unsupported-platform message, not a 3D viewer. Use Chrome/Edge to try
the model on this computer. No model or script is downloaded from a CDN.

Standalone preview, with no login/backend needed:

    flutter run -d chrome -t tool/avatar_preview.dart

Normal app:

    flutter run -d chrome

The preview entrypoint is separate from the production app's authentication.
Mobile runtime rendering and performance still need device testing.

## Size and rotation

The Home model viewport now targets twice its former width/height, capped to
the available screen area on small devices. The avatar-only view uses more
of the screen. This is a presentation change; the GLB geometry is unchanged.
Drag left/right over the avatar to turn the camera through an unrestricted
360 degrees. A tap still toggles the avatar-only view. Dragging changes only
the camera orbit and does not recreate the viewer or restart its animation.
The orbit returns to the front on a new Home entry.

Home dimensions are now shared through `AvatarLayout.home`, at 81% of the
original enlarged viewport (two successive 10% reductions). Shop and wardrobe
interpolate from their compact preview to exactly that Home viewport size as
the item panel collapses from 60% to its minimum. Expanding the panel restores
the compact preview; the same avatar state is retained during resizing.

## Starter wardrobe v9

The app now displays `pacegasus_starter_v9.glb`. Its geometry, rig and animation
binary are identical to v8. A KHR_materials_variants entry changes only the
shirt's charcoal fabric/graphite seams to white/light gray; gold logo and
trim, other clothing, skin and hair are unchanged. Black is the default and
`starter_tee_white` is the selectable white variant.

`backend/src/services/starterAvatarCatalog.js` registers seven free defaults:
hair, face, black tee, white tee, shorts, socks and shoes. After restarting or
redeploying the backend with this code, its existing authenticated avatar
endpoints seed the named catalog idempotently, grant defaults to the current
user (including existing users), and fill empty starter equipment slots.
Existing owned items and saved outfit slots are not overwritten. This assumes
avatar tables from migrations 015/016 are already installed; no unrelated
migrations or direct production database writes were run for this change.

Inventory thumbnails are bundled `asset:` images rendered from the actual
Blender parts. Select an item to preview; save uses the authenticated avatar
API, and Home reloads the saved outfit when returning from another page.
The only new alternative shape/color in this set is the white tee. The other
slots each have their current starter item; arbitrary future catalog meshes,
removing covered body parts, and new garment silhouettes need further assets
and rendering support, not merely catalog rows.

Asset generation: run tools/avatar/build_starter_assets.py in Blender (uses
the original local v8 .blend), then node tools/avatar/export_starter_catalog.js.
The exported starter_catalog.json is a visual-test fixture, not a substitute
for API ownership in the production app.

Memory-only demo with real wardrobe UI and 3D material switching:

    flutter run -d chrome -t tool/wardrobe_preview.dart

Demo saves last only until reload. Production saves remain in the existing
backend avatar equipment tables. Mobile device rendering still needs hardware
testing; web rendering and the scoped API/UI tests were verified.
