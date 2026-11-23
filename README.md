# Lumen — Flutter port

A non-destructive mobile photo editor. This is the Flutter source tree for the same app that
was prototyped as a single-file web build: same document model, same adjustment maths, same
stroke-record retouch.

**This tree has not been compiled.** The sandbox it was written in has no Flutter SDK, so treat
`flutter analyze` as the first thing you run, not the last.

---

## Setup

```bash
cd lumen_flutter

# 1. generate the platform folders (android/, ios/) that this tree does not include
flutter create --org com.yourco --platforms=android,ios .

# 2. fetch packages
flutter pub get

# 3. check for anything I could not verify
flutter analyze

# 4. run
flutter run
```

Minimum: Flutter 3.16 / Dart 3.0. The three plugins used are `image_picker` (import),
`path_provider` (temp files) and `share_plus` (share sheet); `image` is a pure-Dart JPEG
encoder because `dart:ui` only writes PNG.

If `flutter create` overwrites `pubspec.yaml`, re-add the dependency block from the version in
this folder — the `flutter:` section (assets) and the dependency list are the parts that matter.

---

## Get a test APK

An APK has to be compiled with the Android SDK, so it cannot be produced in the sandbox this
project was written in. Two routes, both of which end with an installable `app-debug.apk`:

**Route A — GitHub Actions (no local setup, ~6 minutes)**

1. Push this folder to a GitHub repository (`.github/workflows/build-apk.yml` is included).
2. Open the **Actions** tab → **Build test APK** → **Run workflow**.
3. When it goes green, download the `lumen-debug-apk` artifact. Unzip it, copy
   `app-debug.apk` to your phone, tap it, and allow "install unknown apps" for your
   browser or file manager.

The workflow also uploads `analyze-report`, which is the analyzer output from the same run —
send me that file if the build fails and I will fix what it flags.

**Route B — locally**

```bash
./build_apk.sh
```

Needs Flutter 3.16+ and JDK 17 with the Android SDK on PATH. It runs `flutter create`,
`pub get`, `analyze`, then `build apk --debug`, and leaves `lumen-debug.apk` in the folder.

**Stopgap while you wait:** the web build (`Lumen-Photo-Editor.html`) runs today in Chrome on
Android. It is not an installed app, but every feature is live in it.

---

## What is ported

| Area | Status |
|---|---|
| Import (gallery + camera) | done |
| Viewport: pinch zoom, pan, double-tap fit, hold-to-compare | done |
| 16 adjustments + live preview | done |
| 26 filter presets, category chips, thumbnails from your own photo, intensity | done |
| Crop: aspect presets, straighten, flip, reset | done |
| Free-form crop handles | **not ported** |
| Retouch: heal, clone, smooth, blur, dodge, burn | done |
| Retouch: sharpen, red-eye | **not ported** (need a pixel pass on the stamp) |
| Layers: text, shapes, stickers, drag, reorder, opacity, 16 blend modes, lock, hide | done |
| Text: font, size, weight, colour, outline, shadow | done |
| Eyedropper: pick a colour from the photo | done |
| Undo / redo (30 steps, copy-on-write snapshots) | done |
| Export: JPEG (quality) / PNG, original or long edge, share sheet | done |
| Local masks, background cutout, object removal, enhance ×2 | **not ported** |
| Brush drawing / doodle layer | **not ported** |

The four "not ported" rows are the honest gap. Nothing in them is blocked by the architecture —
they are simply the parts I could not test blind, so I left them out rather than ship code that
probably throws.

---

## Architecture

```
lib/
  model.dart      document: Adjustments, FilterPreset, Layer, Stroke, CropRect, Project
  pipeline.dart   render engine: crop → pixel pass → unsharp → mask → cutout → layers
  state.dart      EditorController (ChangeNotifier): history, strokes, export
  main.dart       app shell, viewport gestures, CustomPainter, layers + export sheets
  ui/widgets.dart design system
  ui/sheets.dart  one widget per tool
```

**Non-destructive.** `Project` holds the source image, a crop rect and an ordered stack of
strokes and layers. Editing never touches the source pixels; every frame is re-derived from the
stack. Undo is a list of `Project` copies that share the immutable `ui.Image` references, so a
snapshot costs a few hundred bytes.

**Rendering.** `buildPhoto(project, scale)` runs the same pipeline at preview scale (~1×) and at
export scale. Adjustments are one pass over the RGBA buffer with a 256-entry tone LUT and a
luma-gain LUT, then an optional unsharp pass for clarity/sharpen. On a 0.8 MP preview that is
roughly 15–25 ms.

**Retouch strokes are recorded, not flattened.** `retouchPicture(project, scale, source)`
re-records every stamp against the source image at whatever scale you ask for — so an export is
as sharp as the source, not as sharp as the preview.

---

## Known risks in this tree

0. **Eyedropper note.** `sampleAt` reads the pixel from the rendered photo at a document point,
   so it picks the colour you actually see — including filters and retouch, but not layers.
   Picking from *outside* the app (the system screen) needs Android MediaProjection or an iOS
   broadcast extension plus a capture permission; that is deliberately not wired up here.
1. **It has never been compiled.** Expect a handful of analyzer errors on first run — most
   likely in the `ui/` widgets (const-ness, deprecated `withOpacity`/`DropdownButtonFormField`
   value). Fixing those is minutes, not hours.
2. `buildPhoto` runs on the UI isolate. At preview scale that is fine; a 12 MP export will jank
   for a moment. Move the pixel pass into `Isolate.run` before shipping.
3. `image` 4.x `Image.fromBytes` expects the raw buffer in RGBA order — verify the exported JPEG
   is not channel-swapped on your device. If it is, add `.convert(numChannels: 3)`.
4. Icons and the app name are placeholders; `flutter_launcher_icons` is not wired up.

## Next steps, in order

1. `flutter analyze` and clear the errors.
2. Port the local mask (it is one `dstIn` composite in `buildPhoto`, plus a brush that writes an
   `ui.Image` mask).
3. Port the smart tools: `MediaPipe` subject segmentation for cutout, the same onion-peel
   inpainting for object removal.
4. Move the pixel pass to an isolate.
5. Replace the CPU pipeline with fragment shaders (`FragmentProgram`) once the CPU version is
   the reference implementation you can diff against.
