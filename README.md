# 11Cam

iPhone 11-style Camera app and features for older iPhones on iOS 15 and 16.

> **Status: 0.1.9.** Tested on iPhone 7 and iPhone 6s (iOS 15.8). iPhone 8 / X on iOS 16,
> and the 7 Plus, still to be tested.

## What you get

- iPhone 11 Camera UI: SF camera font, control drawer, over-content flip button
- QuickTake (hold the shutter for video, drag to lock / zoom)
- Photo aspect ratios (4:3, 16:9, square)
- Exposure slider
- Live Text button (the viewfinder shows it when it detects text)
- iPhone 11 zoom dial, also on single-camera phones
- Portrait (phones that already have Portrait): Depth Control f/1.4–f/16, lighting
  strength slider, High-Key Mono, live Stage Light preview
- Dual-camera phones: View Outside the Frame
- iPhone 7 / 7 Plus: 4K60 and 1080p240
- A10 and older: HD video works with the new UI (see "How it works")
- Settings → Camera shows Apple's own switches for these (QuickTake, Volume Up for
  Burst, Live Text, View Outside the Frame, ...)

Not enabled on purpose: automatic Live Photos (the daemon's scoring needs a Neural Engine),
capture on touch-down (no effect with QuickTake), responsive shutter, Smart HDR, Night mode,
Deep Fusion, Photographic Styles. The camera hardware and daemon on these phones don't support them.

Experiments (`make package EXP="LOWLIGHT STEREO LIGHTINGPREVIEW MODERNHDR LIVETEXT"`, any subset):
auto low-light FPS, stereo audio, live Studio/Contour/Stage lighting preview, iPhone 8-style HDR on
the iPhone 7, Live Text without a Neural Engine. `DIAG=DIAG_LOG` adds diagnostic logs.

## How it works

One dylib, loaded into Camera, Settings and the camera daemon (`mediaserverd`):

- **Camera / Settings.** CameraUI decides every feature in
  `-[CAMCaptureCapabilities initWithHostProcess:]` from AVGestalt answers (a per-model
  table in AVFCapture). While that initializer runs, the tweak answers YES to
  `AVGQDeviceSupportsMomentCapture`, `AVGQHasAppleNeuralEngine` and a few others, and
  CameraUI derives the new UI itself. AVGestalt is untouched outside that initializer
  (in Settings, the Camera pane also asks directly, so there the answers always apply).
- **mediaserverd.** The daemon reads `<model>/AVCaptureSession.plist` and
  `<model>/CameraSetup.plist` through `FigCaptureCFCreatePropertyList(ForModel)`. The
  tweak patches the returned dictionaries in memory (no system files are replaced) and
  clears the daemon's cache of the parsed plist (`com.apple.cameracapture.volatile` →
  `CaptureSourceInfo`), which would otherwise skip the patch.
- **HD on A10 and older.** The new UI's crop preview adds a `BWPreviewStitcherNode` that only
  takes 4:2:0 frames, while HD's stabilisation path on these phones delivers packed 4:2:2
  (`yuvs`). The tweak puts a pixel-transfer converter in front of the stitcher in the daemon's
  capture graph (pass-through when the format already fits).

Firmware notes and the analysis behind this are in [`CLAUDE.md`](CLAUDE.md).

## Building

Requires [Theos](https://theos.dev).

```sh
make package               # rootless (iphoneos-arm64)
make package ROOTFUL=1     # rootful  (iphoneos-arm)
```

## Credits

Michael Melita.
