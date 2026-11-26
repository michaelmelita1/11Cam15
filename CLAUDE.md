# 11Cam15: handoff notes for Claude

`README.md` is the user-facing description; this file is the working context. Maintainer: Michael Melita. Packages ship through the Cydia/Sileo repo `michaelmelita1/michaelmelita1.github.io`.

## Branches

| Branch | What it is |
|---|---|
| `Rootful---0.0.17` | Old rootful build. Two tweaks (`11CamSingle`, `11CamDual`) forcing ~30 `CAMCaptureCapabilities` getters to YES, plus a `postinst` that overwrote `CMCapture.framework/<board>/AVCaptureSession.plist` with hand-edited copies (based on an older iOS). |
| `Rootless-0.0.18` | Old rootless build (repo default). UI getter hooks only. |
| `claude/confident-keller-qrushw` | **Current work: 0.1.0, a from-scratch rewrite** based on firmware analysis. No Settings pane. |

## Design (0.1.0)

One dylib, filter = Camera + Preferences bundles, `mediaserverd`/`cameracaptured` executables. Links only Foundation/CoreFoundation/Substrate (safe in the daemon).

**Client (Camera, Settings).** `-[CAMCaptureCapabilities initWithHostProcess:]` (CameraUI) computes every feature ivar from AVGestalt (`AVGestaltGetBoolAnswer`, `AVGestaltGetIntegerAnswerWithDefault`, `AVGestaltGetFloatAnswerWithDefault`, exported from AVFCapture) and a few MobileGestalt keys. CameraUI reads AVGQ keys nowhere else. The tweak hooks the two AVGestalt getters but only changes answers while that initializer runs (thread-local depth counter), so CameraUI derives a consistent UI and AVFoundation itself is untouched. Overrides:

| AVGestalt key | CameraUI effect |
|---|---|
| `AVGQDeviceSupportsMomentCapture` | `deviceSupportsCTM` → CTM (QuickTake), SF font, over-content flip, control drawer, aspect-ratio crop (`isAspectRatioCropSupported` = `isCTMSupported`), dynamic shutter zoom |
| `AVGQDeviceSupportsExposureBiasWithoutExposureLock` | exposure slider (also requires CTM) |
| `AVGQDeviceSupportsLivePhotoAuto` | auto Live Photo |
| `AVGQHasAppleNeuralEngine` | `neuralEngineSupported` → `imageAnalysisSupported` (Live Text, Camera host only) and `depthEffectApertureSupported` |
| Portrait devices: `PortraitLightEffectFilters`, `PortraitIntensityAdjustments`, `StageLightPortraitPreview`, `Rear/FrontFacingCameraStageLightPortraitCaptureCapability` | lighting, strength slider, lighting version 2 (High-Key Mono), live stage light |
| Dual back camera: `AVGQDeviceSupportsSpatialOverCapture` | `backSpatialOverCaptureSupported` |
| iPhone 7/7 Plus ints: `RearFacingCameraVideoCapture4kMaxFPS` 60, `RearFacingCameraHFRVideoCapture1080pMaxFPS` 240 | 4K60 / 240 fps |

After init, `_zoomPlatterSupported` is set on dual-camera phones (zoom dial; CameraUI only enables it with an ultra-wide). Deliberately not enabled: `ResponsiveShutter`, `CameraCaptureOnTouchDown`, `CameraDeferredProcessing`, `SemanticStyles`, ZSL-related.

**Daemon (mediaserverd).** CMCapture loads `<model>/AVCaptureSession.plist` via exported `FigCaptureCFCreatePropertyList(name)` (from `csu_createSourceInfoDictionariesFromAVCaptureSessionPlist`) and `<model>/CameraSetup.plist` via exported `FigCaptureCFCreatePropertyListForModel(name, model, flag)` (from `-[FigCaptureCameraParameters _readAndPreprocessCameraParametersForModelSpecificName:fromFile:]`). Both tail-call `FigCaptureCFCreatePropertyListForModelAndBundleIdentifier`, which returns +1 (ends in `objc_retain`). The hooks return a patched +1 mutable deep copy.
- The parsed AVCaptureSession.plist is cached in CFPreferences `com.apple.cameracapture.volatile` → `CaptureSourceInfo` and reused while model, build version and attribute version are unchanged. The daemon ctor deletes that key; `postinst`/`postrm` delete the plist file and kill `cfprefsd` + `mediaserverd`.
- AVCaptureSession patch: iPhone 7/7+: drop `Experimental`/`SecondaryScalerUnavailable` from back `UHD60`/`1080p240`. Dual: `ConfigureForSpatialOverCaptureSupport` on `built-in_video:0` `1080p30`; `SpatialOverCaptureSupported` on `built-in_video:3` `12MP` and `1080p30` (created from `720p30`'s depth formats if missing).
- CameraSetup patch: for each `TuningParameters/PortType*/<sensorID>` with `SDOFRenderingParameters`: if `SLM/maximumSimulatedAperture` is 0, set 1.4–16; add `PortraitLightingParameters {min 0, max 1, effect 0.5}` if missing. On the X this hits `PortTypeBackTelephoto` and `PortTypeFrontInfrared` only.
- In the daemon, format getters (`-[FigCaptureSourceVideoFormat isResponsiveShutterSupported]`, `isZeroShutterLagSupported`, `isSpatialOverCaptureSupported`, `minSimulatedAperture`, ...) are plain lookups in the format dictionary. `isMomentCaptureMovieRecordingSupported` is hard-coded YES.

## Firmware facts (iOS 16.7.16 iPhone X, 16.6.1 iPhone 11 Pro)

- Extracted files live on the user's PC in `Downloads/11Cam15-firmware/` (plists per board, `analysis/avgestalt_table.json` = AVGestalt values for all 41 models, `analysis/keymap.txt` = AVGQ key → CAMCaptureCapabilities ivar, `analysis/caps_init.ann` = annotated init disassembly). Apple's files: never commit them.
- AVGestalt per-model table: `AVGestaltGetDeviceFeatures(FigCaptureGetModelSpecificName(), bool, int, float, string dicts)` in AVFCapture, data table at `0x1d76b02f0` in the X 16.7.16 cache.
- iOS 16 X stock already has 4K60, 1080p240, `sphereModeStillActivePreviewSupported`. Hidden formats are marked `Experimental = True`.
- The old hand-edited D221 plist came from an older iOS and drops iOS 16 keys (`stillImageNoiseReductionAndFusionScheme`, moved `PortraitEffectsMatteMainImageDownscalingFactor`). Swapping it in on iOS 16 is a shutter-bug suspect.
- Other shutter-bug suspect: the old tweak forced `isCTMSupported`/`deviceSupportsCTM` getters while the ivars (and everything derived from them in init: control drawer, CTM mode selector, dynamic shutter zoom) stayed NO.
- Camera runs in `mediaserverd` on iOS 16 (no `cameracaptured`).
- The iPhone X 16.7.16 shared cache is in the Cryptex SystemOS image (sealed APFS volume, LZFSE UDIF, LZBITMAP-compressed `.dyldlinkedit`/`.symbols`).

## iOS 15 differences (iOS 15.8.8 iPhone 7, checked)

- Same exports: `AVGestaltGetBoolAnswer`, `AVGestaltGetIntegerAnswer(WithDefault)`, `FigCaptureCFCreatePropertyList(ForModel)`; same `CaptureSourceInfo` cache in `com.apple.cameracapture.volatile`; CameraSetup loaded via `...ForModel`.
- iOS 15 CameraUI reads integers with `AVGestaltGetIntegerAnswer` (no default) -> hooked too.
- No `AVGQDeviceSupportsExposureBiasWithoutExposureLock` on 15: exposure slider = CTM && (!MGIsDeviceOneOfType(list) || pref `CAMFeatureDevelopmentForceExposureSlider`). The tweak answers that pref YES during init (hooks `CFPreferencesGetAppBooleanValue`).
- CTM = `AVGQDeviceSupportsMomentCapture` || pref `CAMFeatureDevelopmentAllowCTMShutterButton` (only suppressed if that pref is explicitly NO). Live Text = Camera host && neural engine && pref `CAMFeatureDevelopmentAllowImageAnalysis` (defaults on). Auto Live Photo = iris && (key || pref `CAMFeatureDevelopmentAllowLivePhotoAutoMode`).
- iPhone 7 (D10/D101) stock: `UHD60` Experimental, `1080p240` Experimental + SecondaryScalerUnavailable; AVGestalt 4K max 30, 1080p HFR max 120. CameraSetup has no SDOF (portrait) tuning, so that patch is a no-op there.
- AVGestalt table (43 models incl. N66/N69/N71/D10/D11/N112) dumped to `Downloads/11Cam15-firmware/analysis/avgestalt15.json`.

## iPhone 7 HD video bug (found with the DIAG_LOG build; 0.1.3 attempt failed, 0.1.4 fix)

- Symptom: with the new UI on, HD 30/60 video glitches and won't record; 4K30/4K60 fine. Session runtime error `AVFoundationErrorDomain -11800` / underlying `-666`, CameraUI retries in a loop.
- Cause: the exposure slider's clipping indicator makes CameraUI add `videoPreviewHistogram` to the metadata output's types. On A10 the HD formats are front-end-scaled (`Video-FES-30/60`, high-res stills via a separate path, cinematic VIS); the extra histogram stream doesn't fit there, it does in 4K (`Video-BES-*`).
- 0.1.3 (clipping indicator off outside photo modes) did NOT fix it: later HD attempts requested only `face` and still failed. `-[CAMRealtimeMetadataCommand executeWithContext:]` calls `setVideoPreviewHistogramMetadataObjectTypesAvailable:YES` (in Photo mode) and never resets it; that flag (1 in failing builds, 0 in no-QuickTake) stays on into Video.
- 0.1.4 fix, A10 and older only (iPhone 7/7+, 6s/6s+, SE, iPod 7): clipping indicator off in all modes, `isVideoPreviewHistogramMetadataSupported` -> NO, `setVideoPreviewHistogramMetadataObjectTypesAvailable:` forced NO, `videoPreviewHistogram` stripped from `setMetadataObjectTypes:`. iPhone 8/X are fine natively (A11 has the headroom) and are untouched. Still to confirm on the iPhone 7.
- Diagnostic builds: `make package DIAG=DIAG_LOG [NOQUICKTAKE=1]` write `/var/mobile/Library/Caches/com.apple.camera/11Cam-diag[-noquicktake].txt` (the only Camera-writable spot that's easy to reach; /var/mobile/Media and Documents are refused by the sandbox).

## Status

- 0.1.0 builds and packages (rootless + rootful), Theos + iPhoneOS16.5 SDK. **Not tested on a device.**
- 0.1.1 adds the iOS 15 fixes above. First device test: iPhone 7, iOS 15, Dopamine (rootless).
- Test plan on a phone: Console filter `11Cam`; expect `client hooks installed`, `AVGestalt overrides: …`, `daemon hooks installed (1/1)`, `enabled simulated aperture range …`. Then check QuickTake, shutter on A11, Depth Control actually changing blur, View Outside the Frame on a dual phone.

## Build

```sh
export THEOS=~/theos
make package             # rootless
make package ROOTFUL=1   # rootful
```

Theos needs `rsync` to copy `layout/DEBIAN/postinst`/`postrm`; without it they're silently left out (check `dpkg-deb -I`).

## Conventions

- Don't import UIKit or link Preferences: the dylib loads into `mediaserverd`.
- Don't write anything under `/System`; patch in memory.
- No model identifiers or personal info in commit messages. Commit messages end with the session's co-author lines.

### iPhone 7 HD bug: root cause candidate (0.1.6)
diag6 showed the only preview difference between the full and no-QuickTake builds: the full build's viewfinder is an
`AVSpatialOverCaptureVideoPreviewLayer` (primaryAndOverCaptureCompositingEnabled=1, primaryCaptureRectAspectRatio=1.333).
`-[CAMCaptureEngine initWithPowerController:options:]` (iOS 15.8: 0x1b6dd5f24) picks that layer when
`isSpatialOverCaptureSupported || isAspectRatioCropSupported`; aspect crop = CTM, so QuickTake drags it in.
0.1.6 answers NO to both only during engine init on A10-and-older, so those phones get the plain preview layer.
The earlier histogram/clipping/digital-flash workarounds (0.1.3-0.1.5) did NOT fix it; remove them once 0.1.6 is confirmed.
0.1.6 confirmed by the user: HD records with the plain preview layer. Kept as the fallback.
-666 origin in the daemon (iOS 15.8 CMCapture): only `-[BWGraph _resolveFormats:]` builds it (NSOSStatusErrorDomain -666),
when a BWNodeConnection's ends have incompatible attached-media keys or `-[BWNodeConnection resolveCommonBufferFormat]` fails.
Daemon diag: `make package DIAG="DIAG_LOG DIAG_KEEP_OVERCAPTURE"` logs failing connections plus graph dumps to 11Cam-daemon-diag.txt.

### iPhone 7 HD bug: real cause and fix (0.1.7)
Daemon diag: source 'VideoCapture' delivers 2304x1296 'yuvs' (ISP-strip VIS needs yuvs/yuvf) through a pass-through
fan-out; the over-capture preview's BWPreviewStitcherNode accepts only 420v/420f/x420/x422/p422 -> resolveCommonBufferFormat fails -> -666.
0.1.7 (group DaemonGraph, A10-and-older only): in -[BWGraph connectOutput:toInput:pipelineStage:], when the input belongs to a
BWPreviewStitcherNode, insert a BWPixelTransferNode (outputPixelFormat 420v, passesBuffersThroughWhenPossible) in front of it.
Removed: 0.1.6 plain-preview client hook and the 0.1.3-0.1.5 histogram/clipping/digital-flash hooks.
If passthrough-when-possible turns out to push 420v upstream, drop setPassesBuffersThroughWhenPossible (always convert).
Note: Logos ignores #ifdef around %hook, so keep optional hooks out or in separate groups.

### Rename (0.1.8)
Display name, tweak/dylib name (11Cam.dylib, 11Cam.plist), log prefix `[11Cam]` and diag files (`11Cam-diag*.txt`, `11Cam-daemon-diag.txt`) are now "11Cam".
The package identifier `com.michaelmelita1.11cam15` and the depiction URLs are deliberately unchanged, so existing installs upgrade in place.
Authors: Michael Melita only (Flylarb and Ezekiel1998 removed at the user's request).

### Feature feasibility (0.1.9~exp1), from iOS 15.8 CMCapture + AVGestalt table + 11 Pro/X/7 plists
Experiments behind `make package EXP="TOUCHDOWN LOWLIGHT STEREO LIGHTINGPREVIEW"` (plain C, so #ifdef works; no new %hooks):
- TOUCHDOWN: AVGQDeviceSupportsCameraCaptureOnTouchDown (CameraUI-only; Apple dev pref CAMFeatureDevelopmentCaptureOnTouchDown).
- LOWLIGHT: AVGQDeviceSupportsAutoLowLightVideo + LowLightVideoCaptureSupported/LowLightVideoAEMaxGain (= Common AEMaxGain x 256/96) on wide/dual 720p30/1080p30/UHD30/4k30.
  Daemon: csp_configureMultiStreamCameraNode uses lowLightVideoCaptureEnabled && isLowLightVideoCaptureSupported, and lowLightVideoAEMaxGain.
- STEREO: AVGQDeviceSupportsStereoAudioRecording + stereoAudioCaptureSupported on built-in_audio:0 -> BWAudioSourceNode setStereoAudioCaptureEnabled. Depends on the audio hardware/tuning.
- LIGHTINGPREVIEW: AVGQDeviceSupportsStudioLightPortraitPreview + Studio/Stage preview-rendering keys on dual 12MP / TrueDepth 7MP,12MP
  (FigCapturePreviewSinkPipeline _appendFilteredPreviewPipeline...; may need inference-engine segmentation).
Ruled out: Responsive shutter (daemon only uses it in the Unified Bracketing still pipeline, A12+; inert on X/8/7);
Smart HDR (HDR v3 = UB-HDR formats/pipeline; X/8 use legacy HDR/GNRHDR); Night mode (DigitalFlash + UB-LowLight + DeepFusion-LowLight;
even the A13 SE 2 lacks it); single-camera Portrait on 8/7 (XR/SE2 only; needs ANE segmentation/monocular depth; AVGQHasAppleNeuralEngine=0 on A11).
0.1.9~exp2: + LIVEAUTO (AVCaptureDeviceCommonSettings.livePhotoVitalityScoringSupported). `make package EXP="..." DIAG=DIAG_LOG` logs "EXP <feature>:" lines:
client (11Cam-diag.txt): capability ivars, shutter touch DOWN/UP vs capturePhotoWithSettings; daemon (11Cam-daemon-diag.txt):
FigCaptureSourceConfiguration setLowLightVideoCaptureEnabled:, BWFigVideoCaptureStream setLowLightVideoEnabled:, FigAudioCaptureConnectionConfiguration
setBuiltInMicrophoneStereoAudioCaptureEnabled:, BWAudioSourceNode setStereoAudioCaptureEnabled:, BWStreamingFilterNode setStudioAndContour/StageRenderingEnabled:,
FigCaptureMovieFileSinkTailPipelineConfiguration setVitalityScoringEnabled:, BWIrisMovieInfo setVitalityScore:/setVitalityScoreValid:.

### 0.1.9~exp3
- Removed: AVGQDeviceSupportsLivePhotoAuto from the main build (vitality scoring = cs_supportsLivePhotoVitalityScoring needs isNeuralEngineSupported),
  TOUCHDOWN (CAMDynamicShutterControl _shouldShortPressOnTouchDown is NO whenever dragging is enabled, i.e. always with QuickTake), LIVEAUTO.
- Settings rows: in Preferences, AVGestalt overrides now apply to every query (sAlwaysOverride) and the AVGestalt hooks go in without
  waiting for CameraUI; caps init also forces _autoLowLightVideoSupported / _stereoAudioRecordingSupported under the experiments.
  Diag in Preferences writes 11Cam-settings-diag.txt (every AVGestalt query + hostProcess).
- MODERNHDR (A10 iPhones): AVGQCameraHDR2Capability + AVGQCameraHDRVersion=2; GNRHDRSupported on wide 12MP/Square;
  X back-sensor (0x0343) GNRParameters Fusion/NoiseModel LTMHDRParameters copied into the 7's back sensor tuning (embedded base64 bplist).
- LIVETEXT: VisionKit caches support in a private global set in a dispatch_once (deviceHasAppleNeuralEngine, or internal-build override).
  EnableLiveText() decodes +[VKImageAnalyzer deviceSupportsImageAnalysis] (a single `b` to vk_imageAnalysisSupportedAndSettingsSwitchEnabled),
  finds that function's first adrp+ldrb (the cached flag, iOS 15.8: VisionKitCore 0x1fa8d9578) and sets it to 1 after the once has run.
- Experiment diag hooks: VKCaptureTextAnalysisRequest init, CAMViewfinderViewController _shouldShowImageAnalysisButtonForGraphConfiguration: /
  _updateTextAnalysisWithInsert:instructions:animated:.

### 6s (N71mAP, iOS 15.8.8) exp4 logs + exp5
- 6s HD uses the same 2304x1296 'yuvs' ISP-strip path as the 7; the stitcher converter is needed and works (all graphs resolved, no -666).
- Both phones: with setOutputPixelFormat:420v the converter showed passthrough=0 in photo mode and converted 420f P3 -> 420v.
  exp5 drops the fixed output format so photo-mode buffers pass through; only 'yuvs' gets converted. Port this to the main build once confirmed.
- Live Text button visible on the 6s with _imageAnalysisButtonAlwaysVisible (ivar name confirmed); no VKCaptureTextAnalysisRequest seen yet.

### More firmware (Downloads/11Cam15-firmware): iPhone6s-15.8.8 (N71/N71m + CameraSettings.bundle), iPhoneSE-15.8.8 (N69/N69u),
iPhone8-16.7.16 (D20/D201), iPhone8Plus-16.7.16 (D21/D211). 7 Plus and 6s Plus (5.5-inch iOS 15) IPSWs not provided yet.
- Back sensors: 7 = 0x0303 (GNR, legacy HDR tone curve); 6s/SE = 0x0247 (no GNR at all -> modern HDR impossible there);
  8 / 8 Plus / X = 0x0343 with byte-identical GNR LTMHDRParameters (so "8 tuning" == "X tuning"). A11 sensors also carry
  NoiseReductionAndSharpeningParameters (incl. HDRParameters) that the 7 lacks.
- Settings Auto Low Light FPS row: CameraSettings calls -[CAMCaptureCapabilities isAutoLowLightVideoSupportedForMode:videoConfiguration:videoEncodingBehavior:]
  = autoLowLightVideoSupported && encodingBehavior < 2 && mode == 1 && configuration in {0,5,6,7} or 10000..10006 (the 30 fps configs),
  i.e. it only shows while a 30 fps Record Video format is selected (4K60/1080p60 hide it), as on the 11.
- iOS 15.8.8 6s shared cache extracted to the device VM /tmp/dsc (with .symbols); ~/tools/chunk6s.sh.

### 7 Plus / 6s Plus / X iOS 15.6.1 / 14 Pro firmware (all in 11Cam15-firmware)
- 7 Plus (D11/D111): same wide (0x0303) and front (0x0314) sensors as the 7, tele 0x0313. Dual-camera formats are overrides on the wide
  camera's; it doesn't list UHD60/1080p240, so un-hiding them on the wide made them appear on the dual too. exp6 marks them Experimental
  on the dual (as the X's dual does), so Camera switches to the wide camera for 4K60/240.
  7 Plus tele SLM has no min/max aperture keys at all (older renderer); our SLM patch still adds 1.4-16 -> Depth Control unverified there.
- 6s Plus (N66/N66m): same sensors/formats as the 6s (Video-FES-30 HD path); CameraSetup only adds OIS long/short NR keys.
- X iOS 15.6.1: same devices/formats as 16.7.16 (our patches apply unchanged); but iOS 15 X still uses legacy HDR tuning
  (HDR_ToneCurveParameters, StillImageNoiseReductionAndStabilizationScheme), 16 uses GNR LTM.
- 14 Pro 16.6.1 (D73) extracted, not analysed (not needed).

### 0.1.10 (cleanup + Live Text in the main build)
- Live Text: EnableLiveText (VisionKit cached-flag patch) is in the main build; the always-visible button is set whenever VisionKit
  needed the patch (no usable Neural Engine = every phone 11Cam supports). EXP_LIVETEXT removed.
- Removed bug-hunt leftovers: NO_QUICKTAKE / NOQUICKTAKE, DIAG_NO_FORMAT_CONTROL, DIAG_NO_SHUTTER_ZOOM, PropertyDump/IvarDump,
  the big HD commitConfiguration dumps, scene-monitoring / digital-flash logging, diag path probing. Daemon graph diag kept.
- Photos depth (f-number) editing, from iOS 16 PhotoImaging: -[PIDepthAdjustmentController canAdjustApertureValue] =
  minimumAperture > 0 && maximumAperture > 0, read from the photo's depth info (getMinMaxSimulatedApertureFrom:..., capture-time
  SLM range). The X/8 Plus/7 Plus SLM range is 0-0, which hides the slider; 11Cam's PatchCameraSetup sets 1.4-16, so new Portrait
  photos should get the slider. Unverified; older photos would need a Photos-side hook (MobileSlideShow + edit extensions).

## 0.1.10~hdrdiag1 (25 Nov 2026)
iPhone 7 Modern HDR test (photos IMG_0047-0054): no HDR in any photo (no maker-note 0x0a), HDR-on/off pairs identical.
Daemon graph: with MODERNHDR the 'Legacy HDR' router port + BWHDRNode are gone (pipeline did switch), GNR node present.
Camera scene monitoring settings showed HDR:2 (auto); actual capture settings were never logged.
hdrdiag1 = experiments-diag + logging: client capturePhotoWithSettings (HDR mode), daemon
-[BWStillImageCoordinatorNode captureStillImageNowWithSettings:], BWGNRNode hdrEnabled/processingLTMHDRFusion,
and per-capture GNR processing type / expected frames / preBracket. Build: EXP="LOWLIGHT STEREO MODERNHDR LIGHTINGPREVIEW" DIAG=DIAG_LOG.
Daemon diag log on iOS 15 lands in /var/mobile/Library/Caches/com.apple.mediaserverd/.
hdrdiag1 results (photos 0055-0058, 2 HDR On + 2 Off): GNR node hdrEnabled=1 processingLTMHDRFusion=1 (pipeline ready),
but every capture resolved to BWStillImageCaptureSettings type:1, capture flags 0, 1 frame -> the capture-type resolver never
picks an HDR bracket. Client capturePhotoWithSettings hook and BWStillImageCoordinatorNode captureStillImageNowWithSettings: never fired.
hdrdiag2 adds: -[BWFigVideoCaptureDevice captureStillImageNowWithSettings:] (FigCaptureStillImageSettings._HDRMode,
_stillImageGNRHDREnabled, _hdrScene, _hdrModeForSceneMonitoring), setStillImageGNRHDREnabled:, and logs the type encoding of
-[BWFigVideoCaptureDevice resolveStillImageCaptureTypeFromStatisticsByPortType:...captureFlags:] (11 args, stack args -> need exact types to hook).
hdrdiag2 BROKE capture: hooking -[BWFigVideoCaptureDevice captureStillImageNowWithSettings:] crashed mediaserverd on every shot
(Camera got AVFoundation -11819 "Cannot Complete Action" = media services reset). Never hook that method blind.
Resolver runtime encoding (iOS 15.8.6): i72@0:8@16i24i28i32i36B40@44B52i56B60^Q64 -> (id stats, int flash, int hdr, int qp,
int stereoFusion, BOOL depth, id types, BOOL burst, int bracket, BOOL forSceneMonitoring, uint64_t *flags) -> int.
hdrdiag3: removed that hook; logs requested _HDRMode from BWGNRNode._currentRequestedStillImageCaptureSettings, and hooks the
resolver with the exact types (logs hdrMode, return captureType, *flags, _stillImageGNRHDREnabled, _hdrScene).
hdrdiag3 RESULT (25 Nov, Auto HDR off in Settings): HDR On -> resolver hdrMode=1 -> captureType=3, GNR expects 3 frames + pre-bracket EV0
(real HDR bracket through GNR/LTM fusion). HDR Off -> type 1, 1 frame. Earlier "no HDR" was Auto HDR (hdrMode=2) with hdrScene=0.
Next: confirm the fused photos look right; then Auto HDR scene detection (hdrScene never set on the 7).
Photos 0060-0065 (hdrdiag3): HDR On shots 0060/0061/0062/0065 all carry maker-note 0x0a=4 (= "Original Image", the kept normal photo);
no file with 0x0a=3 (HDR result) and no IMG number gaps -> the fused HDR image is never delivered/saved. 0060/0062 look identical
to the HDR-off 0063/0064 (dark interior, 60-68% near-black). 0061 is 1/33 s ISO 25, blurry/overexposed (looks like an EV+ bracket frame).
GNR logged processing type=0 with 3 expected frames. Next: find why GNR doesn't output the fused frame (processing type / LTM fusion).
Keep Normal Photo OFF: HDR On still saves a photo with no HDR badge -> fused output still not produced.
iOS16 GNR processing-type logic (sub_1a3da7340): switch on the *stream* captureStreamSettingsForPortType:.captureType (1..5)
+ captureFlags 0x400 + ivars; types 0/2/4/5/6/7/9/10 seen. hdrdiag4 logs per-frame _gnrProcessingTypeWithMetadataDictionary:,
_processSequenceInSampleBufferProcessor (received frames, type, preBracket), handleNodeError:forInput:,
_detectMissingPreBracketedFrameAndEmitBWNodeError, plus method encodings of the GNR callbacks.
hdrdiag4 RESULT: HDR On -> GNR gets all 3 frames + pre-bracket, picks processing type 9 (HDR fusion branch, gated on _hdrEnabled in
the iOS16 disasm), runs _processSequenceInSampleBufferProcessor, no node error. So fusion is attempted by the GNR
sample-buffer processor (C, tuning-driven). Output still unbadged / looks like EV0.
Encodings: _sampleBufferProcessorOutputReady:sampleBuffer: v28@0:8i16^{opaqueCMSampleBuffer=}20 (int status, CMSampleBufferRef).
hdrdiag5 logs processor output status + attachment keys (hdr/ltm/fusion/processing/bracket) and per-frame exposure/EV/gain keys.
Makefile: DIAG builds link CoreMedia.
hdrdiag5 RESULT: GNR sample-buffer processor returns status=-17400 for every HDR On shot; output buffer has GNRProcessingType=0,
PreBracketingFrame=NO (= unmerged fallback frame -> saved photo). Pre-bracket frame metadata: HDRExposureRatio=256, LTMLocked=1,
ExposureTime 0.0599, LuxLevel 63. The GNR SBP lives in the ISP plugin (/System/Library/MediaCapture/H9ISP.mediacapture on A10,
H10ISP on A11). Next: get the iPhone 7 15.8.8 IPSW again and inspect H9ISP for the HDR-fusion path / where -17400 is returned
(likely fusion not implemented for H9 -> hardware/firmware limit).
iPhone 7 15.8.8 cache (P3 IPSW, system dmg 098-68844-067.dmg): images H9ISP.mediacapture 0x1df27e000 (.2), CMCapture 0x1a3ab3000 (.1),
GNR.videoprocessor 0x1e93d8000 (.3, __TEXT 0x3d000). Device-VM copies: /tmp/dsc7/gnr.bin, h9.bin, cmcap.bin; ~/w7/gdis.py, h9dis.py (capstone).
GNR.videoprocessor DOES contain HDR fusion (Fuse, LTMHDRParameters, detectFlickerForHDR, gnr.HDR.ToneMapSaturationFactor).
-17400 is returned at 0x1e93dd478: status = f(storage+0x40): 0 -> ok, 1 -> -17401, 6 -> -17402, anything else -> -17400.
Internal codes set at: 0x13,1 (0x1e93d9444/98), 7,2 (da47c/da4b0), 8 (dd168), 0x12 (df388), 0xb (e664c), 0xe,0x10 (ea69c/ea6d0),
1,6,1 (fb384/fb5d0/fbaf8), 10 (dd22c, ObjC call failing when flag storage+0x3a set).
hdrdiag6 logs internalError = *(int*)(CMBaseObjectGetDerivedStorage(BWGNRNode._sampleBufferProcessor)+0x40) and flag +0x3a.
hdrdiag6: derived storage +0x40 read 29696 (0x7400) = wrong object. The -17400 function (starts 0x1e93dd06c) takes x20 = x0 = an ObjC
object (classes in GNR.videoprocessor: SampleBufferProcessor, GNRProcessor, DenoiseFusePipeline, FusionRemixStage, ...).
hdrdiag7 scans derived storage for a SampleBufferProcessor/GNRProcessor instance and dumps its int/bool ivars (names + offsets).
hdrdiag7 RESULT: GNRProcessor (storage+0x0) _fusionAlgo=3 _isMultiFrameProcessing=1 _hasBeenSetup=1 _aggregateErr=17.
Error 17 set at 0x1e93fb4bc (method starting 0x1e93fb410): if _fusionAlgo==3 (and state @0x8a78 sign bit clear):
  byte self+0x2350 == 0 -> err 17; else byte self+0x1230 != 1 -> err 17. Those fields are only read there (written via struct copy).
X 15 and X 16 GNRParameters/Fusion are identical except stereo-fusion keys; our patch already adds X LTMHDRParameters to
Fusion and NoiseModel. hdrdiag8 dumps every GNRProcessor ivar (name/offset/type) once + bytes @0x1230/@0x2350.
ROOT CAUSE (hdrdiag8, 25 Nov): error 17 = missing LTM curves. Offsets 0x1230/0x2350 = _prebracketedProperties/_evmProperties
.metadataHasLtmCurves (frameProperties_t +0xa0). Set at 0x1e93d9910 from parser 0x1e93e8694, which needs three frame-metadata
keys (CFData blobs): LTMLookUpTables (8x6 grid x 33 entries -> ltmLut[1584]), GlobalLTMLookUpTable (257), GlobalToneCurveLookUpTable (257).
Blob header: u16 version (1..4 or 1001); dims u16 @+2/@+4 minus padding u16 @+0xe/+0x10 and @+0xa/+0xc; entry count u16 @+0x16.
H9ISP.mediacapture (iPhone 7 ISP plugin) GOT references only GlobalToneCurveLookUpTable -> it never attaches LTMLookUpTables or
GlobalLTMLookUpTable; frames only carry AverageLTM (33 values) + LTMLocked. H9ISP has "EnableLTMLuts"/"Shared LTM LUTs" strings.
Fix options: synthesize the two blobs from AverageLTM (uniform grid, approximation) in the daemon before GNR; best to first log a
real blob from an iPhone X/8 on iOS 16 to copy the exact format. Device-VM helper: ~/w7/rd4.sh ADDR LEN OUT (reads any cache address).
LTM tables are per-frame ISP output, not stored in firmware. X_SystemOS.dmg in _work is EMPTY (0 bytes); used XS iOS16 cache instead:
H10ISP.mediacapture (used by A11/A12) extracted to device-VM /tmp/h10. It imports kFigCaptureStreamMetadata_LTMLookUpTables,
_GlobalLTMLookUpTable, _GlobalToneCurveLookUpTable, kFigCaptureStreamProperty_LTMLookUpTableMetadataEnabled,
kFigCaptureStreamStillImageCaptureNowKey_DeliverLTMLookUpTableMetadata; has SetLTMLookUpTableMetadataEnabled (0x1f7084a80),
CopyLTMLookUpTableMetadataEnabled, "Unable to enable LTM LUT metadata while streaming is active", "EnableLTMLuts", "Shared LTM LUTs".
H9ISP (iPhone 7) has "EnableLTMLuts" + "Shared LTM LUTs" too but no metadata export -> firmware may compute the LUTs; plugin never
exports them. Real-fix path: find H9's Shared LTM LUTs buffer per frame and build the blobs from it (port of H10's export).
H9ISP deep dive (25 Nov): firmware metadata tag "Shared LTM LUTs" exists for A10 (dumper at 0x1df2d22f8): valid u16@0,
lutsCountX@2, lutsCountY@4, LUT data @6..0x5a06, then u16 isDataPadded@0x5a06, lutsCountXPadded@0x5a08, lutsCountYPadded@0x5a0a,
stride@0x5a0c, lutEntries@0x5a0e, top/bottom/left/rightPadding @0x5a10/12/14/16. (H10 tag is the same shape, data to 0x8a06.)
Only the debug dumper reads it; AverageLTM (key id 0x82) comes from a different tag ([tags+0x40] u16 @0x282..0x2c4, 33 values).
Debug defaults (domain com.apple.coremedia, read by H9 at init into settings struct 0x1fa09a760): EnableLTMLuts (@+0x18) ->
firmware cmd 0x126 enable metadata section 0x13 (0x1df2b55c4) at stream start; H9ISPRawMetaInDict (@+0x40) -> raw metadata dict.
hdrdiag9: hooks CFPreferencesCopyValue in mediaserverd to return 1 for those two keys; logs every frame metadata key with type/size.
GNR needs keys LTMLookUpTables / GlobalLTMLookUpTable (CFData blobs) - next build would construct them from the firmware tag.
hdrdiag9 RESULT: forcing EnableLTMLuts + H9ISPRawMetaInDict works (no instability reported). Frame metadata now has
RawMetaData data[68608] (raw firmware metadata) and GlobalToneCurveLookUpTable data[516]; still no LTMLookUpTables /
GlobalLTMLookUpTable keys. hdrdiag10 saves RawMetaData / GlobalToneCurveLookUpTable / ISPHallData of the first 6 GNR frames to
/var/mobile/Library/Caches/com.apple.mediaserverd/11Cam-frameN-<key>.bin and logs AverageLTM, for offline parsing of the
"Shared LTM LUTs" section (0x5a18 bytes expected) inside RawMetaData.
expdiag11 (= hdrdiag10 + experiment diagnostics), build EXP="LOWLIGHT STEREO MODERNHDR LIGHTINGPREVIEW" DIAG=DIAG_LOG:
- Camera: session snapshot prints fps range; after each recording the delegate's didFinishRecording is swizzled and the file is
  analysed (size, nominalFPS, per-frame duration histogram, audio channels/sample rate/format/layout) -> "EXP recording:" lines.
- mediaserverd: BWStreamingFilterNode changeToFilters:animated:, setPortraitLightingEffectStrength:, renderSampleBuffer count
  every 150 frames with active filters, handleNodeError:forInput: -> "EXP lightingpreview:" lines.
Makefile DIAG builds link CoreMedia AVFoundation.
FOUND THE CURVES (25 Nov, hdrdiag10 files): RawMetaData (68608 B) holds the "Shared LTM LUTs" section at offset 0xadc4:
valid=1, 8x6 grid, isDataPadded=0, lutEntries=33, padded 11x9 (pads 1,2,1,2), 48 contiguous monotonic 33-pt curves that differ per
zone (real local tone mapping). GlobalToneCurveLookUpTable format: u16 count(257) + 257 u16. AverageLTM (33 pts) = firmware
"ltmGlobalCurve" (Shared RGB Proc tag) -> resampled to 257 for GlobalLTMLookUpTable.
GNR LTMLookUpTables blob, version 1: u16 version=1, xPadded, yPadded, rowStride bytes, entriesPerLUT (33/60), top, bottom, left,
right, 2 reserved, data @+0x16; entry addr = data + (row+top)*stride + (col+left)*entries*2 + e*2 (accessors 0x1e93eb254 data,
0x1e93fab00 top, 0x1e93fab28 stride, 0x1e93eb2e4 left, 0x1e93e7c8c bytes/LUT, 0x1e93fab50 entries; v3/v4 differ).
FIX (EXP_MODERNHDR, A10 iPhones): mediaserverd hooks CFPreferencesCopyValue (com.apple.coremedia EnableLTMLuts /
H9ISPRawMetaInDict -> 1); %group ModernHDRDaemon hooks -[BWGNRNode renderSampleBuffer:forInput:] and adds LTMLookUpTables +
GlobalLTMLookUpTable to the sample buffer's "MetadataDictionary" attachment (AddLTMTablesToSampleBuffer). CoreMedia always linked.
Test build: 0.1.10~hdrfix1 (EXP all + DIAG).
hdrfix1 RESULT (IMG_0093 orig 0x0a=4 / IMG_0094 HDR 0x0a=3): HDR MERGE WORKS (blown laptop screen recovered: clip 9.9% -> 0.3%)
but output ~0.21-0.30x the original's encoded values in shadows/mids (mean 87 -> 41) - darker than "LTM undone" alone; a near-constant
ratio suggests the fused image stays at the dark (EV-) frame's exposure. Prime suspect: HDRExposureRatio=256 (1.0) on the 7's frames
(firmware hdrRatio not set for brackets), so GNR doesn't scale the EV- domain back up. Daemon log was lost: mediaserverd restarted
(also one -11819 crash at 18:37:32). hdrfix2: diag log now keeps <name>-previous.txt across restarts; logs every GNR input frame
(pre, ExposureTime, AGC, ispDGain, sensorDGain, ExposureBias, HDRExposureRatio, lux, AverageLTM[16], GTC samples).
Logs kept getting lost: mediaserverd restarts around each Camera launch (cause unknown - get crash reports), the diag log was
truncated on each start, and /tmp == /var/tmp so the file was opened twice (duplicate lines; "-previous" rotation clobbered itself).
hdrfix3: logs now APPEND across restarts (reset only past 4 MB), duplicate real paths skipped. The iPhone 7 IPSW has been deleted
from Downloads (rd4.sh no longer works). Raw-data check: the only 257-pt curve in RawMetaData is the GTC (@0x2ba6); AverageLTM sits
at 0x2e04 with a small header -> A10 global LTM really is 33 pts (H10 has 257).
NOTE: DiagLog forward declaration is near the top of Tweak.x - don't use it as an end marker for edits.
hdrfix3 RESULT: log intact. GNR status 0 (merge OK) both shots. A10 HDR bracket = pre-bracket EV0 (real GTC) + EV0 / EV-2 / EV+2
frames (ExposureBias 0/-2/2; bracket frames carry a sqrt GTC 32768/46340/56755). Exposure products (time*AGC*ispDGain):
EV0 0.0399*2048*300, EV-2 0.03*744*275 (ratio 3.997), EV+2 0.0599*2048*800 (ratio 0.250). HDRExposureRatio = 256 on ALL frames.
hdrfix4: AddLTMTablesToSampleBuffer also sets HDRExposureRatio = round(EV0product/product*256) on bracket frames (bias != 0),
falling back to 2^-bias if the measurement is off by >1.6x. Remembers EV0 product from pre-bracket / bias-0 frames.
MODERN HDR REMOVED (25 Nov): hdrfix4 looked worse than the 7's stock HDR; user asked to strip it. All EXP_MODERNHDR code,
LTM export, CFPreferences hook and the HDR diag hooks are gone; last full source kept in research/Tweak-modernhdr-attempt.x,
summary in research/ModernHDR-A10.md. README updated. All builds (main, rootful, EXP, DIAG, EXP+DIAG) compile.
LOW LIGHT FPS CONFIRMED (IMG_0114/0115, iPhone 7): 1080p30 with switch on records 25 fps in the dark, ramps 25->27->30 when
brighter and back to 25 (203 frames @25, 139 @30) - dynamic like the 11.
STEREO: daemon audio source goes stereo (lpcm 2 ch) but files are 1 ch AAC (layout 0x640001 mono). Audio encoder settings come
from FigCaptureMovieFileRecordingSettings.audioSettings (client outputSettings). 0.1.11~stereo1: %group StereoDaemon (EXP_STEREO)
tracks FigAudioCaptureConnectionConfiguration setBuiltInMicrophoneStereoAudioCaptureEnabled: and, when requested, rewrites
audioSettings AVNumberOfChannelsKey 1 -> 2 + AVChannelLayoutKey Stereo (bitrate x2 if < 128k). Diag logs client audio output
settings, the daemon settings before/after, and +[BWAudioFormat formatForAVAudioSettings:inputFormat:]. AVFoundation now always linked.
ExposureControl has no low-light FPS (XS doesn't support it natively); could be added the same way.
STEREO RESULT (IMG_0116, 0.1.11~stereo1, iPhone 7): file now 2 ch AAC 192k stereo layout, but L == R sample-for-sample (corr 1.0,
0.0 dB on every snap). Graph is 2 ch lpcm end to end -> the A10 mic source itself delivers dual mono (no stereo polar pattern).
User: disable stereo on A10 and older -> client override, ivar, daemon stereoAudioCaptureSupported and StereoDaemon %init all gated
on !IsA10OrOlder() (8/8 Plus/X keep it, unconfirmed). Camera plists: X vs XS/11 Pro mic entry differ only by
stereoAudioCaptureSupported=true. User downloading iPhone X 16.7.x + XS 16.x IPSWs to compare audio configs (polar patterns).

## Stereo X vs XS IPSW comparison (Nov 2026)
See research/Stereo-X-vs-XS.md. Apple gates stereo with the device-tree flag product/audio/stereo-sound-recording=1 (XS only);
mic hardware is identical. User decision: leave the stereo experiment on A11 as unconfirmed until tested on X and 8. No code change.
If the X test shows dual mono, next step is faking the device-tree flag for the audio daemon.

### 0.1.12
View Outside the Frame moved from the main build to the experiment EXP_OVERCAPTURE (client gestalt AVGQDeviceSupportsSpatialOverCapture +
daemon format keys), since it's untested on any dual-camera phone. HasDualBackCamera is __attribute__((unused)) so the main build compiles.
Experiments build: EXP="STEREO LIGHTINGPREVIEW OVERCAPTURE".

## Release builds (user preference, from 0.1.12 on)
Only ship two debs per release: the rootless main build (`make package`) and the rootless experiments+diag build
(`make package EXP="STEREO LIGHTINGPREVIEW OVERCAPTURE" DIAG=DIAG_LOG`, renamed *-experiments-diag.deb). Plus the source zip.
No rootful or plain diag builds unless asked.

### 0.1.13
Auto Low Light FPS promoted to main (Tweak.x defines EXP_LOWLIGHT unconditionally near the includes; code paths unchanged).
Experiments build: EXP="STEREO LIGHTINGPREVIEW OVERCAPTURE" DIAG=DIAG_LOG.
- Newer Logos (Mac Theos) breaks one-line hooks ending "%orig; }": keep hook bodies multi-line.

## 0.2.0: ExposureControl merged into 11Cam (one package, per-device features)
- IsA12Phone() (D321AP, D331AP, D331pAP, N841AP) -> former ExposureControl set; everything else -> 11Cam set. BoolOverrides returns
  early for A12. A12 already has CTM/QuickTake (iOS 14+) and real Live Text, so no CTM/ANE overrides, no EnableLiveText, no stereo.
- Daemon: PatchCaptureSessionA12 (livePhotoVitalityScoringSupported, View Outside the Frame on XS via AddOverCaptureKeys, EXP_NIGHTMODE);
  PatchCameraSetup: A12 -> Night mode tuning only (EXP), else SDOF/portrait params. DeviceWithUniqueIDSuffix also matches iOS 18 uniqueName.
- CFPreferencesGetAppBooleanValue hook iOS 15 only (crashed Camera on XS iOS 18); AVGestalt integer hooks only when IntegerOverrides non-empty (A10).
- ARCHS arm64 arm64e -> build on the Mac (~/Downloads/tweaks/11Cam15/build.sh: main + experiments-diag). control Conflicts/Replaces exposurecontrol.
- Diag: VitalityDiag group (A12), View Outside the Frame runtime method logging (OverCaptureWatched: XS, or A9-A11 with EXP_OVERCAPTURE).
- XR now also gets the single-camera zoom-dial hook (_shouldUseZoomControlInsteadOfSlider). Untested on XR.
- ExposureControl repo is superseded; its CLAUDE.md history still applies to the A12 code.
- 0.2.1: View Outside the Frame moved into main for A9-A11 dual-camera phones (user request; untested on 7 Plus / 8 Plus / X). EXP list: STEREO LIGHTINGPREVIEW NIGHTMODE.
- Feature table (user request): kPhones[] rows {name, hw.model list, min/max iOS major, Feature bitmask}; Features()/Has(f) used everywhere
  instead of IsA10iPhone/IsA10OrOlder/IsXS/IsA12Phone/HasDualBackCamera. Experiments are bits masked by kBuiltExperiments.
  Unsupported model or iOS outside the row's range -> %ctor returns without hooking. View Outside the Frame is in main for 7 Plus/8 Plus/X.
  Version stays 0.2.0 (nothing released since the merge).

## Hidden-format sweep (all firmware in Downloads/11Cam15-firmware, Nov 2026)
Experimental formats left hidden on purpose (user decided not worth it): wide 4k30 (4096x2304), 3k30 (6s/SE), 1080p30-CinemaScope (2592x1080),
3:2 photo (4096x2732, 6s/SE/7), Square photo (rear+front). Dual-camera high-fps formats (UHD60/1080p240/1080p120/720p240) are hidden on the
dual device by design (Camera switches to the wide). XS has nothing else hidden. Only 7/7+ UHD60/1080p240 are worth unlocking (already done).
