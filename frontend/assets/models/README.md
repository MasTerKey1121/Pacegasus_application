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
