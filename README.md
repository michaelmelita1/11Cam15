# 11Cam

iPhone 11 Camera App & Font for older iPhones

iPhone 11 Camera UI (SF camera font, control drawer)

Zoom Dial (iPhone 11 Style), now on single-camera phones too

Photo Aspect Ratios (4:3, 16:9, Square)

QuickTake + QuickTake Zoom

Exposure Slider (adjust exposure without locking)

Live Text (button always visible; reads text from the captured frame)

HD Video (1080p / 720p) working with the new UI on A9 and A10

4K60 and 1080p240 on iPhone 7 and 7 Plus

Auto Low Light FPS (Settings → Camera → Record Video, shows with a 30 fps format selected)

Settings → Camera shows Apple's own switches for these features

NOTE: DUAL CAMERAS ARE NEEDED FOR THE FOLLOWING ADDITIONS

Portrait Depth Control (f/1.4 – f/16), also adjustable afterwards in Photos for new Portrait photos (to be confirmed)

Portrait Lighting with High Key Mono, Intensity Control and live Stage Light preview

## Experimental (separate builds)

Stereo Audio Recording (iPhone 8 / 8 Plus / X only, unconfirmed; the iPhone 7 and older just record the same mono sound on both channels)

Live Studio / Contour / Stage Light preview in Portrait

View Outside the Frame (dual-camera phones, unconfirmed)

## Download from my repo

https://michaelmelita1.github.io

## Compatibility

iPhone SE - iPhone X (6s, 6s Plus, SE, 7, 7 Plus, 8, 8 Plus, X), iPod 7

iOS 15 - 16, rootless and rootful

Tested on iPhone 7 and iPhone 6s (iOS 15.8). iPhone 8 / X on iOS 16 and the 7 Plus still to be tested.

## Credits

Thanks to Poomsmart (60fps) and u/lilacvibes_, whose code earlier versions were built on

## BUGS TO FIX

~~Fix the damn shutter bug on A11 devices~~ FIXED

~~Fix 1080p recording on A9, A10~~ FIXED (properly, in the camera daemon)

## THINGS TO ADD

Portrait Bokeh Editing in Photos app: Photos shows the f-number slider when a photo records an aperture range; 11Cam's Depth Control should add it to new Portrait photos (to be confirmed)

~~Live Text Detection (Instead of a constant Button)~~ Needs the Neural Engine, not possible on A9 - A11. The constant button is back

~~Photographic Styles (Possibly to do with Semanitic Styles)~~ ISP DEPENDANT, not possible

~~Auto Live Photos~~ The camera daemon's scoring needs the Neural Engine, removed

~~Night Mode / Deep Fusion / Smart HDR~~ Need A12 / A13 hardware

~~iPhone 8 style HDR on the iPhone 7~~ Got it merging using the 7's own tone-mapping data, but the results looked worse than the 7's own HDR, so it's removed (notes in research/)

## HOW IT WORKS

One dylib for Camera, Settings and the camera daemon (mediaserverd). It answers the camera feature questions the Camera app asks at launch (no method-by-method hooks), and patches the daemon's camera config in memory (no system files are replaced). Details and firmware notes are in [CLAUDE.md](CLAUDE.md).

## TO BUILD

make package (rootless)

make package ROOTFUL=1 (rootful)

make package EXP="STEREO LIGHTINGPREVIEW OVERCAPTURE" (experiments, any subset)

make package DIAG=DIAG_LOG (diagnostic logs)
