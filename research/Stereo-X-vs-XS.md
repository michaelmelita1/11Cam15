# Stereo recording: iPhone X vs XS (IPSW comparison)

IPSWs: iPhone X 16.7.16 (20H392, d22ap), iPhone XS 16.6.1 (20G81, d321ap).

## Same on both
- audio-codec mic entries identical (fmic-mic=2051, imic-mic=1, lmic-mic=4, smic-mic=1794, same micbias), builtin-mics = 4.
- Both kernels contain "stereo-sound-recording" and the same polar/stereo strings.

## XS only (device tree product/audio)
- stereo-sound-recording = 1  <- the capability flag
- mic-trim-gains = syscfg/MiGa (per-unit factory mic calibration)
- speaker-trim-gains, speaker-thiele-small, supports-spatial-facetime, supports-advanced-vp-chatflavor

## X only (audio-codec)
- acoustic-trim-gains = syscfg/ATGa (possibly older form of mic calibration, unconfirmed)

## Camera plist
- XS/11 Pro mic entry has stereoAudioCaptureSupported; X does not.

## Status
Stereo experiment left enabled on A11 (8 / 8 Plus / X) as UNCONFIRMED until tested on a real X and 8.
The A10 (iPhone 7) source is dual-mono, so stereo is disabled there.
Likely outcome on the X: the camera-side override alone gives mono on both channels, because the audio system also
checks the device-tree flag. A real fix would also need stereo-sound-recording faked for the audio daemon.
