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
