# 11Cam
iPhone 11 Camera App for older iPhones


# Features
iPhone 11 Camera UI (SF camera font, control drawer)

Zoom Dial (iPhone 13 Style for dual camera phones, iPhone XS style for single camera phones)

Photo Aspect Ratios (4:3, 16:9, Square)

QuickTake + QuickTake Zoom

Exposure Slider (adjust exposure without locking)

4K60 and 1080p240 on iPhone 7 and 7 Plus

Settings → Camera shows Apple's own switches for these features

NOTE: DUAL CAMERAS ARE NEEDED FOR THE FOLLOWING ADDITIONS

Portrait Depth Control (f/1.4 – f/16)

Portrait Lighting with High Key Mono, Intensity Control and live Stage Light preview



## Experiments to Test

Live Text (button always visible; reads text from the captured frame)

Auto Low Light FPS (Settings → Camera → Record Video, shows with a 30 fps format selected)

Stereo Audio Recording

Auto HDR, iPhone 8 style (iPhone 7 only)

(iPhone 7+, 8+, X)

Live Studio / Contour / Stage Light preview in Portrait

View Outside the Frame (iPhone 7+, 8+, X)

## Download from my repo

https://michaelmelita1.github.io

## Compatibility

iPhone SE - iPhone X (6s, 6s Plus, SE, 7, 7 Plus, 8, 8 Plus, X), iPod 7

iOS 15 - 16, rootless and rootful

Tested on iPhone 7 and iPhone 6s (iOS 15.8). iPhone 8 / X on iOS 16 and the 7 Plus still to be tested.

## THINGS TO FIX

Portrait Bokeh Editing in Photos app

Shutter bug on A11 devices

~~Fix 1080p recording on A9, A10~~ FIXED (properly this time, in the camera daemon)


## NOT POSSIBLE - ALREADY TESTED

~~Live Text Detection (Instead of a constant Button)~~ Needs the Neural Engine, not possible on A9 - A11. Constant button works

~~Photographic Styles (Possibly to do with Semanitic Styles)~~ ISP DEPENDANT, not possible

~~Auto Live Photos~~ The camera daemon's scoring needs the Neural Engine, removed

~~Night Mode / Deep Fusion / Smart HDR~~ Need A12 / A13 hardware
