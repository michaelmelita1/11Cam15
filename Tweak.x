#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
// 11Cam: iPhone 11-style Camera app and features for older iPhones (iOS 15/16).
//
// How it works (from reading the iOS 16 CameraUI, AVFCapture and CMCapture code):
//
// 1. Camera app / Settings (client side)
//    -[CAMCaptureCapabilities initWithHostProcess:] builds every Camera feature flag
//    from AVGestalt answers (a per-model table inside AVFCapture). While that one
//    initializer runs, we change a few AVGestalt answers, so CameraUI derives the
//    whole new UI consistently by itself (QuickTake, SF camera font, aspect ratios,
//    exposure slider, control drawer, Live Text, Depth Control, ...). Outside that
//    initializer AVGestalt is untouched, so AVFoundation's own behaviour is Apple's
//    (Settings is the exception: its Camera pane also asks AVGestalt directly).
//
// 2. Camera daemon (mediaserverd)
//    The daemon reads <model>/AVCaptureSession.plist and <model>/CameraSetup.plist
//    through FigCaptureCFCreatePropertyList / ...ForModel. We patch the returned
//    dictionaries in memory (no files are replaced). The daemon caches its parsed
//    AVCaptureSession.plist in com.apple.cameracapture.volatile -> CaptureSourceInfo,
//    so that cache is cleared at daemon start, otherwise the plist is never re-read.
//
//    A10 and older: the new UI's crop preview needs 4:2:0 frames that HD video's
//    stabilisation path doesn't deliver; a converter is added to the daemon's capture
//    graph in front of the preview stitcher (see "Daemon side: preview stitcher").
//
// 3. Live Text: VisionKit decides once per process that it needs a Neural Engine; see
//    EnableLiveText. On these phones text is read from a captured frame (the button
//    stays visible), not detected live in the viewfinder.
//
// Deliberately NOT enabled: automatic Live Photos and live text detection (need a Neural
// Engine), capture-on-touch-down (no effect with QuickTake), responsive shutter, Smart HDR,
// Night mode, Deep Fusion, Photographic Styles (need A12+ hardware and processing).

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <os/log.h>
#import <substrate.h>

#define LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[11Cam] " fmt, ##__VA_ARGS__)

#ifdef DIAG_LOG
static void DiagLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void DiagLogCapabilities(id caps);
static void DiagInstall(void);
#endif

#pragma mark - Device info

static NSString *HWModel(void) {
	static NSString *model;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		char buf[32] = {0};
		size_t len = sizeof(buf) - 1;
		if (sysctlbyname("hw.model", buf, &len, NULL, 0) == 0) model = [NSString stringWithUTF8String:buf]; // e.g. "D221AP"
		if (!model) model = @"";
	});
	return model;
}

// iPhone 7 / 7 Plus (A10). Their 4K60 and 1080p240 formats exist but are hidden.
static BOOL IsA10iPhone(void) {
	NSString *m = HWModel();
	for (NSString *p in @[@"D10AP", @"D101AP", @"D11AP", @"D111AP"])
		if ([m isEqualToString:p]) return YES;
	return NO;
}

// A10 and older (iPhone 7/7 Plus, 6s/6s Plus, SE, iPod touch 7th gen).
static BOOL IsA10OrOlder(void) {
	NSString *m = HWModel();
	for (NSString *p in @[@"D10AP", @"D101AP", @"D11AP", @"D111AP", @"N71AP", @"N71mAP", @"N66AP", @"N66mAP", @"N69AP", @"N69uAP", @"N112AP"])
		if ([m isEqualToString:p]) return YES;
	return NO;
}

#pragma mark - Client side: AVGestalt answers during CAMCaptureCapabilities init

static __thread int sCapsInitDepth; // > 0 only while -[CAMCaptureCapabilities initWithHostProcess:] runs
// In Settings the Camera pane also asks AVGestalt directly, so overrides apply to every query there.
static BOOL sAlwaysOverride;

static BOOL (*orig_AVGestaltGetBoolAnswer)(CFStringRef question);
static long long (*orig_AVGestaltGetIntegerAnswerWithDefault)(CFStringRef question, long long defaultValue);

static BOOL OrigBool(NSString *q) {
	return orig_AVGestaltGetBoolAnswer ? orig_AVGestaltGetBoolAnswer((__bridge CFStringRef)q) : NO;
}

__attribute__((unused)) static BOOL HasDualBackCamera(void) {
	return OrigBool(@"AVGQDeviceHasAggregateCamera") && OrigBool(@"AVGQRearFacingTelephotoCameraCapability");
}

static NSDictionary<NSString *, NSNumber *> *BoolOverrides(void) {
	static NSDictionary *overrides;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableDictionary *o = [NSMutableDictionary dictionary];

		// The new Camera UI. In CameraUI this one answer becomes deviceSupportsCTM, which
		// drives QuickTake, the SF camera font, the over-content flip button, the control
		// drawer, aspect-ratio crop, the CTM mode selector and dynamic shutter zoom.
		o[@"AVGQDeviceSupportsMomentCapture"] = @YES;
		// Exposure slider (needs the CTM UI above).
		o[@"AVGQDeviceSupportsExposureBiasWithoutExposureLock"] = @YES;
		// CameraUI enables Live Text (imageAnalysis) and Depth Control
		// (depthEffectAperture) from this answer.
		o[@"AVGQHasAppleNeuralEngine"] = @YES;

		// Portrait extras, only where the phone already has Portrait mode.
		BOOL rearPortrait = OrigBool(@"AVGQRearFacingCameraPortraitModeCapability");
		BOOL frontPortrait = OrigBool(@"AVGQFrontFacingCameraPortraitModeCapability");
		if (rearPortrait || frontPortrait) {
			o[@"AVGQDeviceSupportsPortraitLightEffectFilters"] = @YES;   // Portrait Lighting
			o[@"AVGQDeviceSupportsPortraitIntensityAdjustments"] = @YES; // lighting strength slider; also makes CameraUI use lighting version 2 (High-Key Mono)
			o[@"AVGQDeviceSupportsStageLightPortraitPreview"] = @YES;    // live Stage Light preview
		}
		if (rearPortrait) o[@"AVGQRearFacingCameraStageLightPortraitCaptureCapability"] = @YES;
		if (frontPortrait) o[@"AVGQFrontFacingCameraStageLightPortraitCaptureCapability"] = @YES;

		// ---- Experiments (`make package EXP="LOWLIGHT STEREO LIGHTINGPREVIEW OVERCAPTURE"`) ----
#ifdef EXP_LOWLIGHT
		// Auto low-light FPS for 30 fps video (Settings > Camera > Record Video). The daemon
		// side adds LowLightVideoCaptureSupported/LowLightVideoAEMaxGain to the formats.
		o[@"AVGQDeviceSupportsAutoLowLightVideo"] = @YES;
#endif
#ifdef EXP_STEREO
		// Stereo audio in video (XR and later). The daemon side marks the microphone as
		// stereo-capable; Apple's dev switch is CAMFeatureDevelopmentAllowStereoAudioRecording.
		// Not on A10 and older: the iPhone 7 only fills both channels with the same mono signal.
		if (!IsA10OrOlder()) o[@"AVGQDeviceSupportsStereoAudioRecording"] = @YES;
#endif
#ifdef EXP_OVERCAPTURE
		// View Outside the Frame, only on dual-camera phones; the daemon side adds the
		// matching format keys (see PatchExperiments). Untested on a 7 Plus / 8 Plus / X.
		if (HasDualBackCamera()) o[@"AVGQDeviceSupportsSpatialOverCapture"] = @YES;
#endif
#ifdef EXP_LIGHTINGPREVIEW
		// Live Studio/Contour Light preview in Portrait (Stage is above). The daemon side
		// turns on the preview renderer's Studio/Contour and Stage paths.
		if (rearPortrait || frontPortrait) o[@"AVGQDeviceSupportsStudioLightPortraitPreview"] = @YES;
#endif

		overrides = [o copy];
		LOG("model %{public}@, AVGestalt overrides: %{public}@", HWModel(), [[overrides allKeys] componentsJoinedByString:@", "]);
	});
	return overrides;
}

static NSDictionary<NSString *, NSNumber *> *IntegerOverrides(void) {
	static NSDictionary *overrides;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableDictionary *o = [NSMutableDictionary dictionary];
		if (IsA10iPhone()) {
			// Matches the formats the daemon side un-hides on iPhone 7 / 7 Plus.
			o[@"AVGQRearFacingCameraVideoCapture4kMaxFPS"] = @60;
			o[@"AVGQRearFacingCameraHFRVideoCapture1080pMaxFPS"] = @240;
		}
		overrides = [o copy];
	});
	return overrides;
}

static BOOL hook_AVGestaltGetBoolAnswer(CFStringRef question) {
	BOOL answer = orig_AVGestaltGetBoolAnswer(question);
	if ((sCapsInitDepth > 0 || sAlwaysOverride) && question) {
		NSNumber *o = BoolOverrides()[(__bridge NSString *)question];
		if (o) answer = o.boolValue;
	}
#ifdef DIAG_LOG
	if (sAlwaysOverride && question) DiagLog(@"Settings AVGestalt bool %@ -> %d", (__bridge NSString *)question, answer);
#endif
	return answer;
}

static long long OverriddenInteger(CFStringRef question, long long answer) {
	if ((sCapsInitDepth > 0 || sAlwaysOverride) && question) {
		NSNumber *o = IntegerOverrides()[(__bridge NSString *)question];
		if (o && o.longLongValue > answer) answer = o.longLongValue;
	}
#ifdef DIAG_LOG
	if (sAlwaysOverride && question) DiagLog(@"Settings AVGestalt int %@ -> %lld", (__bridge NSString *)question, answer);
#endif
	return answer;
}

// iOS 16 CameraUI uses ...WithDefault, iOS 15 CameraUI uses the plain getter.
static long long hook_AVGestaltGetIntegerAnswerWithDefault(CFStringRef question, long long defaultValue) {
	return OverriddenInteger(question, orig_AVGestaltGetIntegerAnswerWithDefault(question, defaultValue));
}

static long long (*orig_AVGestaltGetIntegerAnswer)(CFStringRef question);
static long long hook_AVGestaltGetIntegerAnswer(CFStringRef question) {
	return OverriddenInteger(question, orig_AVGestaltGetIntegerAnswer(question));
}

// iOS 15 CameraUI only shows the exposure slider on phones missing from a built-in
// device list, unless Apple's developer preference CAMFeatureDevelopmentForceExposureSlider
// is set. Answer YES to that preference while the capabilities are built.
static Boolean (*orig_CFPreferencesGetAppBooleanValue)(CFStringRef key, CFStringRef app, Boolean *valid);
static Boolean hook_CFPreferencesGetAppBooleanValue(CFStringRef key, CFStringRef app, Boolean *valid) {
	if (sCapsInitDepth > 0 && key && CFEqual(key, CFSTR("CAMFeatureDevelopmentForceExposureSlider"))) {
		if (valid) *valid = true;
		return true;
	}
	return orig_CFPreferencesGetAppBooleanValue(key, app, valid);
}

static void SetBoolIvar(id obj, const char *name, BOOL value) {
	Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
	if (!iv) { LOG("ivar %{public}s not found", name); return; }
	*(BOOL *)((uint8_t *)(__bridge void *)obj + ivar_getOffset(iv)) = value;
}


@interface CAMViewfinderViewController : NSObject // UIViewController; declared minimally so UIKit stays out of the daemon
@end

// Live Text. CameraUI shows the Live Text button from AVGQHasAppleNeuralEngine (above), but
// VisionKit makes its own decision once per process, in a private dispatch_once that checks for
// a Neural Engine, and caches the answer in a private global. +[VKImageAnalyzer
// deviceSupportsImageAnalysis] is a single branch to vk_imageAnalysisSupportedAndSettingsSwitchEnabled,
// whose first byte-load (adrp + ldrb) reads that cached global. After the once has run, set it to YES.
// Text recognition itself then runs without the Neural Engine (VisionKit's own "no ANE" path).
static BOOL sLiveTextPatched; // VisionKit needed the change (no usable Neural Engine)
static void EnableLiveText(void) {
	static BOOL done;
	if (done) return;
	done = YES;
	Class analyzer = objc_getClass("VKImageAnalyzer");
	SEL sel = NSSelectorFromString(@"deviceSupportsImageAnalysis");
	Method m = analyzer ? class_getClassMethod(analyzer, sel) : NULL;
	if (!m) { LOG("live text: VKImageAnalyzer not found"); return; }
	BOOL before = ((BOOL (*)(id, SEL))objc_msgSend)(analyzer, sel); // also runs VisionKit's once
	if (before) { LOG("live text: already supported"); return; }
	uint32_t *imp = (uint32_t *)method_getImplementation(m);
	if ((imp[0] & 0xFC000000) != 0x14000000) { LOG("live text: unexpected code, leaving it"); return; }
	int32_t off = ((int32_t)(imp[0] << 6)) >> 6;
	uint32_t *fn = imp + off;
	for (int k = 0; k < 32; k++) {
		uint32_t a = fn[k], b = fn[k + 1];
		if ((a & 0x9F000000) != 0x90000000) continue;
		uint32_t rd = a & 31;
		if ((b & 0xFFC00000) != 0x39400000 || ((b >> 5) & 31) != rd) continue; // ldrb wN, [xRd, #imm]
		int64_t imm = (int64_t)(((a >> 29) & 3) | (((a >> 5) & 0x7FFFF) << 2));
		if (imm & (1 << 20)) imm -= (1 << 21);
		uint8_t *flag = (uint8_t *)((((uintptr_t)&fn[k]) & ~(uintptr_t)0xfff) + (imm << 12) + ((b >> 10) & 0xfff));
		*flag = 1;
		sLiveTextPatched = YES;
		BOOL after = ((BOOL (*)(id, SEL))objc_msgSend)(analyzer, sel);
		LOG("live text: VisionKit support flag set, deviceSupportsImageAnalysis %d -> %d", before, after);
#ifdef DIAG_LOG
		DiagLog(@"livetext: VisionKit deviceSupportsImageAnalysis %d -> %d (the second value also needs Live Text switched on in Settings > General > Language & Region)", before, after);
#endif
		return;
	}
	LOG("live text: flag not found, leaving it");
}

%group Capabilities
%hook CAMCaptureCapabilities
- (id)initWithHostProcess:(long long)hostProcess {
	sCapsInitDepth++;
	id me = %orig;
	sCapsInitDepth--;
	// iPhone 11-style zoom dial. CameraUI only enables it with an ultra-wide camera.
	// (Its style, zoomDialStyle, already follows the new UI once QuickTake is on.)
	if (me) SetBoolIvar(me, "_zoomPlatterSupported", YES);
	if ([[[NSProcessInfo processInfo] processName] isEqualToString:@"Camera"]) EnableLiveText();
	// Live text detection in the viewfinder needs the Neural Engine, but Live Text on a captured
	// frame works. Keep the Live Text button visible so it can always be tapped.
	if (me && sLiveTextPatched) SetBoolIvar(me, "_imageAnalysisButtonAlwaysVisible", YES);
#ifdef EXP_LOWLIGHT
	if (me) SetBoolIvar(me, "_autoLowLightVideoSupported", YES);
#endif
#ifdef EXP_STEREO
	// CameraUI only allows stereo for some host processes; Settings may not be one of them.
	if (me && !IsA10OrOlder()) SetBoolIvar(me, "_stereoAudioRecordingSupported", YES);
#endif
#ifdef DIAG_LOG
	DiagLog(@"CAMCaptureCapabilities initWithHostProcess:%lld", hostProcess);
	if (me) DiagLogCapabilities(me);
#endif
	return me;
}
%end

// Single-camera phones get the slider instead of the zoom control the dial lives in,
// because -[CAMCaptureCapabilities isZoomControlSupported] needs a second camera.
// Keep the rest of Apple's condition: not in image-picker mode, or standard controls shown.
%hook CAMViewfinderViewController
- (BOOL)_shouldUseZoomControlInsteadOfSlider {
	if (%orig) return YES;
	BOOL picker = [self respondsToSelector:@selector(isEmulatingImagePicker)] && ((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(isEmulatingImagePicker));
	BOOL standard = [self respondsToSelector:@selector(isShowingStandardControls)] && ((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(isShowingStandardControls));
	return !picker || standard;
}
%end
%end

static BOOL sClientHooked, sGestaltHooked;

static void HookGestaltIfReady(void) {
	if (sGestaltHooked) return;
	void *getBool = dlsym(RTLD_DEFAULT, "AVGestaltGetBoolAnswer");
	if (!getBool) return;
	void *getIntWithDefault = dlsym(RTLD_DEFAULT, "AVGestaltGetIntegerAnswerWithDefault");
	void *getInt = dlsym(RTLD_DEFAULT, "AVGestaltGetIntegerAnswer");
	sGestaltHooked = YES;
	MSHookFunction(getBool, (void *)hook_AVGestaltGetBoolAnswer, (void **)&orig_AVGestaltGetBoolAnswer);
	if (getIntWithDefault) MSHookFunction(getIntWithDefault, (void *)hook_AVGestaltGetIntegerAnswerWithDefault, (void **)&orig_AVGestaltGetIntegerAnswerWithDefault);
	if (getInt) MSHookFunction(getInt, (void *)hook_AVGestaltGetIntegerAnswer, (void **)&orig_AVGestaltGetIntegerAnswer);
	MSHookFunction((void *)CFPreferencesGetAppBooleanValue, (void *)hook_CFPreferencesGetAppBooleanValue, (void **)&orig_CFPreferencesGetAppBooleanValue);
	LOG("AVGestalt hooks installed");
}

static void HookClientIfReady(void) {
	// Settings: hook AVGestalt as soon as it's loaded, whether or not CameraUI is.
	if (sAlwaysOverride) {
		HookGestaltIfReady();
#ifdef DIAG_LOG
		if (sGestaltHooked) DiagInstall();
#endif
	}
	if (sClientHooked || !objc_getClass("CAMCaptureCapabilities")) return;
	HookGestaltIfReady();
	if (!sGestaltHooked) { LOG("AVGestaltGetBoolAnswer not found; leaving Camera untouched"); return; }
	sClientHooked = YES;
	%init(Capabilities);
#ifdef DIAG_LOG
	DiagInstall();
#endif
	LOG("client hooks installed");
}

static void ClientImageAdded(const struct mach_header *mh, intptr_t slide) {
	HookClientIfReady(); // Settings loads CameraUI lazily, when the Camera pane opens
}

// Key-value lookup that never throws (CMCapture internals, read for logging and graph edits).
static id V(id obj, NSString *key) {
	if (!obj) return nil;
	@try { return [obj valueForKey:key]; } @catch (NSException *e) { return nil; }
}
@interface BWGraph : NSObject
- (BOOL)connectOutput:(id)output toInput:(id)input pipelineStage:(id)stage;
@end

#pragma mark - Diagnostic logging (only in `make package DIAG=DIAG_LOG`)

#ifdef DIAG_LOG
// Camera writes 11Cam-diag.txt to every writable folder of a list (in practice
// /var/mobile/Library/Caches/com.apple.camera), Settings 11Cam-settings-diag.txt and the
// camera daemon 11Cam-daemon-diag.txt.
#define DIAG_FILE @"11Cam-diag.txt"
static NSMutableArray<NSString *> *sDiagPaths;   // files we can write
static NSMutableArray<NSString *> *sDiagTried;   // every path tried, with the result
static NSMutableString *sDiagBuffer;             // the whole log, so a late-found location gets everything
static dispatch_queue_t sDiagQueue;

// Try to create `path`; if it works, write the whole log so far and keep appending to it.
static NSMutableSet *sDiagRealPaths;
static void DiagTryPath(NSString *path) {
	dispatch_async(sDiagQueue, ^{
		if (!path || [sDiagPaths containsObject:path]) return;
		// /tmp is a link to /var/tmp: don't open the same file twice.
		NSString *real = [[[path stringByDeletingLastPathComponent] stringByResolvingSymlinksInPath] stringByAppendingPathComponent:path.lastPathComponent];
		if (!sDiagRealPaths) sDiagRealPaths = [NSMutableSet set];
		if ([sDiagRealPaths containsObject:real]) { [sDiagTried addObject:[NSString stringWithFormat:@"%@=same file", path]]; return; }
		// Append to the existing log so a daemon restart (or crash) keeps the earlier sessions; start over only past 4 MB.
		NSFileManager *fm = [NSFileManager defaultManager];
		NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
		if (attrs && [attrs fileSize] > 4 * 1024 * 1024) [fm removeItemAtPath:path error:NULL];
		BOOL ok = NO; NSError *err = nil;
		if (![fm fileExistsAtPath:path]) ok = [@"" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:&err];
		NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
		if (h) { [h seekToEndOfFile]; [h writeData:[[@"\n" stringByAppendingString:sDiagBuffer] dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; ok = YES; }
		[sDiagTried addObject:[NSString stringWithFormat:@"%@=%@", path, ok ? @"ok" : (err.localizedDescription ?: @"failed")]];
		if (ok) { [sDiagPaths addObject:path]; [sDiagRealPaths addObject:real]; }
	});
}

static void DiagLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void DiagLog(NSString *fmt, ...) {
	va_list ap; va_start(ap, fmt);
	NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
	va_end(ap);
	LOG("diag: %{public}@", msg);
	if (!sDiagQueue) return;
	NSString *text = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
	NSData *line = [text dataUsingEncoding:NSUTF8StringEncoding];
	dispatch_async(sDiagQueue, ^{
		[sDiagBuffer appendString:text];
		for (NSString *path in sDiagPaths) {
			NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
			if (!h) continue;
			[h seekToEndOfFile];
			[h writeData:line];
			[h closeFile];
		}
	});
}

static id SafeValue(id obj, NSString *key) {
	@try { return [obj valueForKey:key]; } @catch (NSException *e) { return nil; }
}

static NSString *SessionSnapshot(id session) {
	NSMutableString *s = [NSMutableString string];
	[s appendFormat:@"preset=%@ running=%@ interrupted=%@", SafeValue(session, @"sessionPreset"), SafeValue(session, @"running"), SafeValue(session, @"interrupted")];
	for (id input in SafeValue(session, @"inputs") ?: @[]) {
		id dev = SafeValue(input, @"device");
		if (!dev) { [s appendFormat:@"\n    input %@", NSStringFromClass([input class])]; continue; }
		CMTime mn = kCMTimeInvalid, mx = kCMTimeInvalid;
		if ([dev respondsToSelector:@selector(activeVideoMinFrameDuration)]) { mn = [dev activeVideoMinFrameDuration]; mx = [dev activeVideoMaxFrameDuration]; }
		[s appendFormat:@"\n    input %@ activeFormat=%@ fps=%.2f-%.2f zoom=%@",
			SafeValue(dev, @"localizedName"), SafeValue(dev, @"activeFormat"),
			CMTIME_IS_VALID(mx) && CMTimeGetSeconds(mx) > 0 ? 1.0 / CMTimeGetSeconds(mx) : 0.0,
			CMTIME_IS_VALID(mn) && CMTimeGetSeconds(mn) > 0 ? 1.0 / CMTimeGetSeconds(mn) : 0.0,
			SafeValue(dev, @"videoZoomFactor")];
	}
	for (id output in SafeValue(session, @"outputs") ?: @[]) {
		[s appendFormat:@"\n    output %@", NSStringFromClass([output class])];
		for (NSString *k in @[@"movieRecordingEnabled", @"livePhotoCaptureEnabled", @"highResolutionCaptureEnabled", @"recording"]) {
			if ([output respondsToSelector:NSSelectorFromString(k)] || [output respondsToSelector:NSSelectorFromString([@"is" stringByAppendingString:[[k substringToIndex:1].uppercaseString stringByAppendingString:[k substringFromIndex:1]]])]) {
				id v = SafeValue(output, k);
				if (v) [s appendFormat:@" %@=%@", k, v];
			}
		}
		for (id conn in SafeValue(output, @"connections") ?: @[]) {
			[s appendFormat:@"\n        connection enabled=%@ active=%@ stabilizationPreferred=%@ active=%@",
				SafeValue(conn, @"enabled"), SafeValue(conn, @"active"),
				SafeValue(conn, @"preferredVideoStabilizationMode"), SafeValue(conn, @"activeVideoStabilizationMode")];
		}
	}
	return s;
}

static void DiagLogCapabilities(id caps) {
	NSMutableString *s = [NSMutableString stringWithString:@"CAMCaptureCapabilities:"];
	for (NSString *iv in @[@"_ctmSupported", @"_deviceSupportsCTM", @"_ctmSupportSuppressed", @"_allowControlDrawer", @"_allowDynamicShutterZoom",
	                       @"_interactiveVideoFormatControlSupported", @"_interactiveVideoFormatControlAlwaysEnabled", @"_exposureSliderSupported",
	                       @"_autoLowLightVideoSupported", @"_stereoAudioRecordingSupported", @"_backLiveStageLightSupported", @"_frontLiveStageLightSupported",
	                       @"_imageAnalysisSupported", @"_imageAnalysisButtonAlwaysVisible", @"_backHDRSupported", @"_backAutomaticHDRSupported",
	                       @"_modernHDRSupported", @"_HDRSettingAllowed", @"_sfCameraFontSupported", @"_zoomPlatterSupported"]) {
		Ivar v = class_getInstanceVariable(object_getClass(caps), iv.UTF8String);
		if (v) [s appendFormat:@" %@=%d", [iv substringFromIndex:1], *(BOOL *)((uint8_t *)(__bridge void *)caps + ivar_getOffset(v))];
	}
	DiagLog(@"%@", s);
}

// Analyse a finished recording: video size / frame rate / frame-duration spread (low-light FPS, 4K60, 240 fps) and
// audio channels / format (stereo).
static void AnalyseMovie(NSURL *url) {
	if (!url) return;
	AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
	NSMutableString *s = [NSMutableString stringWithFormat:@"EXP recording: %@ duration=%.2fs", url.lastPathComponent, CMTimeGetSeconds(asset.duration)];
	for (AVAssetTrack *t in [asset tracksWithMediaType:AVMediaTypeVideo]) {
		[s appendFormat:@" | video %.0fx%.0f nominalFPS=%.2f minFrameDuration=%.4f", t.naturalSize.width, t.naturalSize.height, t.nominalFrameRate, CMTimeGetSeconds(t.minFrameDuration)];
		NSError *err = nil;
		AVAssetReader *r = [AVAssetReader assetReaderWithAsset:asset error:&err];
		AVAssetReaderTrackOutput *o = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:t outputSettings:nil];
		o.alwaysCopiesSampleData = NO;
		if (r && [r canAddOutput:o]) {
			[r addOutput:o];
			if ([r startReading]) {
				int n = 0; double mind = 1e9, maxd = 0, sum = 0; CMSampleBufferRef sb;
				NSMutableDictionary *hist = [NSMutableDictionary dictionary];
				while ((sb = [o copyNextSampleBuffer])) {
					double d = CMTimeGetSeconds(CMSampleBufferGetDuration(sb));
					if (d > 0) { n++; sum += d; if (d < mind) mind = d; if (d > maxd) maxd = d;
						NSNumber *fps = @(lround(1.0 / d)); hist[fps] = @([hist[fps] intValue] + 1); }
					CFRelease(sb);
				}
				[s appendFormat:@" frames=%d avgFPS=%.2f fastest=%.2ffps slowest=%.2ffps fpsHistogram=%@", n, n && sum > 0 ? n / sum : 0, maxd > 0 ? 1 / mind : 0, maxd > 0 ? 1 / maxd : 0,
					[[hist description] stringByReplacingOccurrencesOfString:@"\n" withString:@""]];
			}
			[r cancelReading];
		}
	}
	for (AVAssetTrack *t in [asset tracksWithMediaType:AVMediaTypeAudio]) {
		for (id fd in t.formatDescriptions) {
			const AudioStreamBasicDescription *a = CMAudioFormatDescriptionGetStreamBasicDescription((__bridge CMAudioFormatDescriptionRef)fd);
			size_t ls = 0; const AudioChannelLayout *lay = CMAudioFormatDescriptionGetChannelLayout((__bridge CMAudioFormatDescriptionRef)fd, &ls);
			if (a) [s appendFormat:@" | audio %u ch %.0f Hz format '%c%c%c%c' layoutTag=0x%x", (unsigned)a->mChannelsPerFrame, a->mSampleRate,
				(char)(a->mFormatID >> 24), (char)(a->mFormatID >> 16), (char)(a->mFormatID >> 8), (char)a->mFormatID, lay ? (unsigned)lay->mChannelLayoutTag : 0];
		}
	}
	DiagLog(@"%@", s);
}

static void HookRecordingDelegate(id delegate) {
	static NSMutableSet *done;
	if (!delegate) return;
	if (!done) done = [NSMutableSet set];
	Class c = object_getClass(delegate);
	SEL sel = @selector(captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:);
	if ([done containsObject:NSStringFromClass(c)]) return;
	[done addObject:NSStringFromClass(c)];
	Method m = class_getInstanceMethod(c, sel);
	if (!m) { DiagLog(@"EXP recording: delegate %@ has no finish callback", NSStringFromClass(c)); return; }
	__block IMP orig = NULL;
	IMP repl = imp_implementationWithBlock(^(id me, id output, NSURL *url, NSArray *conns, NSError *error) {
		DiagLog(@"EXP recording: finished %@ error=%@", url.path, error);
		AnalyseMovie(url);
		((void (*)(id, SEL, id, NSURL *, NSArray *, NSError *))orig)(me, sel, output, url, conns, error);
	});
	orig = method_setImplementation(m, repl);
	DiagLog(@"EXP recording: watching %@ for finished recordings", NSStringFromClass(c));
}

%group Diag
@interface VKCaptureTextAnalysisRequest : NSObject
@end
// Live Text checks.
%hook VKCaptureTextAnalysisRequest
- (id)initWithImage:(id)image focusQuad:(id)quad delegate:(id)delegate {
	DiagLog(@"livetext: Camera started a text analysis request (delegate %@)", NSStringFromClass([delegate class]));
	return %orig;
}
%end
%hook CAMViewfinderViewController
- (BOOL)_shouldShowImageAnalysisButtonForGraphConfiguration:(id)configuration {
	BOOL r = %orig;
	DiagLog(@"livetext: show Live Text button = %d", r);
	return r;
}
- (void)_updateTextAnalysisWithInsert:(id)insert instructions:(BOOL)instructions animated:(BOOL)animated {
	DiagLog(@"livetext: text detection result %@", insert ? @"FOUND TEXT" : @"none");
	%orig;
}
%end
%hook AVCaptureSession
- (void)commitConfiguration {
	%orig;
	DiagLog(@"commitConfiguration: %@", SessionSnapshot(self));
}
- (void)startRunning {
	DiagLog(@"startRunning");
	%orig;
}
- (void)stopRunning {
	DiagLog(@"stopRunning");
	%orig;
}
%end

%hook AVCaptureMovieFileOutput
- (void)startRecordingToOutputFileURL:(NSURL *)url recordingDelegate:(id)delegate {
	DiagLog(@"movie startRecording: %@", url.path);
	for (AVCaptureConnection *c in [(AVCaptureMovieFileOutput *)self connections])
		for (AVCaptureInputPort *port in c.inputPorts)
			if ([port.mediaType isEqualToString:AVMediaTypeAudio])
				DiagLog(@"EXP stereo: client audio output settings %@", [[[(AVCaptureMovieFileOutput *)self outputSettingsForConnection:c] description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
	HookRecordingDelegate(delegate);
	%orig;
}
- (void)stopRecording {
	DiagLog(@"movie stopRecording");
	%orig;
}
%end
%end

static void DiagStart_(NSString *file, NSArray<NSString *> *dirs);
static void DiagInstall(void) {
	static BOOL done;
	if (done) return;
	done = YES;
	if ([[[NSProcessInfo processInfo] processName] isEqualToString:@"Preferences"]) {
		DiagStart_(@"11Cam-settings-diag.txt", @[@"/var/mobile/Library/Caches/com.apple.camera", @"/var/mobile/Library/Caches", @"/var/mobile/Media", @"/var/tmp", NSTemporaryDirectory()]);
		return;
	}
	if ([[[NSProcessInfo processInfo] processName] isEqualToString:@"Camera"]) {
		// The Camera sandbox allows these (not /var/mobile/Media or Documents).
		DiagStart_(DIAG_FILE, @[@"/var/mobile/Library/Caches/com.apple.camera", NSTemporaryDirectory(), @"/var/tmp"]);
		for (NSString *name in @[@"AVCaptureSessionRuntimeErrorNotification", @"AVCaptureSessionWasInterruptedNotification",
		                         @"AVCaptureSessionInterruptionEndedNotification", @"AVCaptureSessionDidStartRunningNotification",
		                         @"AVCaptureSessionDidStopRunningNotification"]) {
			[[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
				DiagLog(@"%@ userInfo=%@ session=%@", n.name, n.userInfo, SessionSnapshot(n.object));
			}];
		}
		%init(Diag);
	}
}

static void DiagStart_(NSString *file, NSArray<NSString *> *dirs) {
	sDiagQueue = dispatch_queue_create("11cam.diag", DISPATCH_QUEUE_SERIAL);
	sDiagPaths = [NSMutableArray array];
	sDiagTried = [NSMutableArray array];
	sDiagBuffer = [NSMutableString stringWithFormat:@"==== 11Cam diagnostic log, %@\n", [NSDate date]];
	for (NSString *dir in dirs) DiagTryPath([dir stringByAppendingPathComponent:file]);
	DiagLog(@"---- %@ started, model %@, iOS %@, home %@, tmp %@", [[NSProcessInfo processInfo] processName], HWModel(),
		[[NSProcessInfo processInfo] operatingSystemVersionString], NSHomeDirectory(), NSTemporaryDirectory());
	dispatch_async(sDiagQueue, ^{ DiagLog(@"log locations tried: %@", [sDiagTried componentsJoinedByString:@" | "]); });
}

#pragma mark - Daemon-side diagnostics: why mediaserverd's capture graph fails (-666)

// -[BWGraph _resolveFormats:] returns -666 when a node connection can't agree on a buffer
// format (-[BWNodeConnection resolveCommonBufferFormat] fails) or the two ends' attached
// media (extra buffers riding along with each frame) don't match. Log which connection,
// what each end asks for, and the whole graph around it.
@interface BWNodeConnection : NSObject
@end


static NSString *FourCCs(id list) {
	if (![list isKindOfClass:[NSArray class]]) return list ? [list description] : @"-";
	NSMutableArray *out = [NSMutableArray array];
	for (id n in list) {
		if (![n isKindOfClass:[NSNumber class]]) { [out addObject:[n description]]; continue; }
		uint32_t v = [n unsignedIntValue];
		char c[5] = { (char)(v >> 24), (char)(v >> 16), (char)(v >> 8), (char)v, 0 };
		BOOL printable = YES;
		for (int i = 0; i < 4; i++) if (c[i] < 32 || c[i] > 126) printable = NO;
		[out addObject:printable ? [NSString stringWithUTF8String:c] : [NSString stringWithFormat:@"%u", v]];
	}
	return [out componentsJoinedByString:@","];
}

static NSString *OneLine(id obj) {
	if (!obj) return @"-";
	return [[[obj description] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
}

static NSString *DescribeRequirements(id req) {
	if (!req) return @"-";
	NSMutableString *s = [NSMutableString stringWithFormat:@"<%@", NSStringFromClass([req class])];
	if ([req respondsToSelector:NSSelectorFromString(@"supportedPixelFormats")]) {
		[s appendFormat:@" %@x%@ pix=[%@] pref=[%@] align w%@ h%@ row%@ cache=%@ color=%@",
			V(req, @"width"), V(req, @"height"), FourCCs(V(req, @"supportedPixelFormats")), FourCCs(V(req, @"preferredPixelFormats")),
			V(req, @"widthAlignment"), V(req, @"heightAlignment"), V(req, @"bytesPerRowAlignment"),
			OneLine(V(req, @"supportedCacheModes")), OneLine(V(req, @"supportedColorSpaceProperties"))];
	}
	[s appendFormat:@"> %@", OneLine(req)];
	return s;
}

static NSString *DescribeNode(id node) {
	if (!node) return @"(no node)";
	return [NSString stringWithFormat:@"%@ '%@' type=%@/%@", NSStringFromClass([node class]), V(node, @"name"), V(node, @"nodeType"), V(node, @"nodeSubType")];
}

static NSString *DescribePort(id port, NSString *label) {
	return [NSString stringWithFormat:@"    %@ %@ port '%@' media=%@ passthrough=%@ keys=%@ resolvedKeys=%@\n      requires %@\n      format %@\n",
		label, DescribeNode(V(port, @"node")), V(port, @"name"), V(port, @"mediaType"), V(port, @"passthroughMode"),
		OneLine(V(port, @"specifiedAttachedMediaKeys")), OneLine(V(port, @"resolvedAttachedMediaKeys")),
		DescribeRequirements(V(port, @"formatRequirements")), OneLine(V(port, @"format"))];
}

static NSString *DescribeConnection(id conn) {
	return [NSString stringWithFormat:@"  CONNECTION %p\n%@%@", conn, DescribePort(V(conn, @"output"), @"from"), DescribePort(V(conn, @"input"), @"to  ")];
}

static const void *kGraphOutputs = &kGraphOutputs;
static int sGraphDumpsOK, sGraphDumpsFailed;

%group DaemonDiag
// Experiment checks (daemon side).
%hook FigCaptureSourceConfiguration
- (void)setLowLightVideoCaptureEnabled:(BOOL)e { DiagLog(@"EXP lowlight: client asked for low-light video = %d", e); %orig; }
%end
%hook BWFigVideoCaptureStream
- (void)setLowLightVideoEnabled:(BOOL)e { DiagLog(@"EXP lowlight: camera stream low-light video = %d", e); %orig; }
%end
%hook FigAudioCaptureConnectionConfiguration
- (void)setBuiltInMicrophoneStereoAudioCaptureEnabled:(BOOL)e { DiagLog(@"EXP stereo: client asked for stereo audio = %d", e); %orig; }
%end
%hook BWAudioSourceNode
- (void)setStereoAudioCaptureEnabled:(BOOL)e { DiagLog(@"EXP stereo: audio source node stereo = %d", e); %orig; }
%end
@interface BWAudioFormat : NSObject
@end
%hook BWAudioFormat
+ (id)formatForAVAudioSettings:(id)settings inputFormat:(CMFormatDescriptionRef)input {
	id r = %orig;
	const AudioStreamBasicDescription *a = input ? CMAudioFormatDescriptionGetStreamBasicDescription(input) : NULL;
	DiagLog(@"EXP stereo: encoder format for input %u ch -> %@", a ? (unsigned)a->mChannelsPerFrame : 0, [[r description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
	return r;
}
%end
%hook BWStreamingFilterNode
- (void)setStudioAndContourRenderingEnabled:(BOOL)e { DiagLog(@"EXP lightingpreview: live Studio/Contour rendering = %d", e); %orig; }
- (void)setStageRenderingEnabled:(BOOL)e { DiagLog(@"EXP lightingpreview: live Stage rendering = %d", e); %orig; }
- (void)changeToFilters:(id)filters animated:(BOOL)animated {
	DiagLog(@"EXP lightingpreview: change to filters %@", [[filters description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
	%orig;
}
- (void)setPortraitLightingEffectStrength:(float)strength {
	DiagLog(@"EXP lightingpreview: lighting effect strength %.2f", strength);
	%orig;
}
- (void)renderSampleBuffer:(CMSampleBufferRef)sbuf forInput:(id)input {
	static unsigned long n;
	%orig;
	if (n++ % 150 == 0) {
		id me = (id)self;
		id f = [me respondsToSelector:@selector(filters)] ? ((id (*)(id, SEL))objc_msgSend)(me, @selector(filters)) : nil;
		DiagLog(@"EXP lightingpreview: filter node rendered %lu frames, active filters: %@", n, [[f description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
	}
}
- (void)handleNodeError:(id)error forInput:(id)input {
	DiagLog(@"EXP lightingpreview: filter node error %@", error);
	%orig;
}
%end
%hook BWGraph
- (BOOL)_resolveFormats:(id *)error {
	BOOL ok = %orig;
	NSArray *outputs = objc_getAssociatedObject(self, kGraphOutputs);
	BOOL dump = ok ? sGraphDumpsOK++ < 8 : sGraphDumpsFailed++ < 4;
	DiagLog(@"BWGraph %p _resolveFormats -> %@ (%lu connections)%@", self, ok ? @"OK" : @"FAILED (-666)", (unsigned long)outputs.count, dump ? @"" : @" [dump limit reached]");
	if (dump) {
		NSMutableString *s = [NSMutableString string];
		for (id output in outputs) { id conn = V(output, @"connection"); if (conn) [s appendString:DescribeConnection(conn)]; }
		DiagLog(@"GRAPH %p (%@):\n%@", self, ok ? @"resolved" : @"FAILED", s);
	}
	return ok;
}
%end
%hook BWNodeConnection
- (BOOL)resolveCommonBufferFormat {
	BOOL ok = %orig;
	if (!ok) DiagLog(@"resolveCommonBufferFormat FAILED:\n%@", DescribeConnection(self));
	return ok;
}
%end
%end

static void DaemonDiagInstall(void) {
	DiagStart_(@"11Cam-daemon-diag.txt", @[@"/var/mobile/Library/Caches/com.apple.camera", @"/var/mobile/Library/Caches/com.apple.mediaserverd",
	                                       @"/var/mobile/Library/Caches", @"/var/mobile/Media", @"/var/mobile/Documents", NSTemporaryDirectory(),
	                                       @"/var/tmp", @"/tmp", @"/var/mobile/Library/Logs"]);
	if (objc_getClass("BWGraph") && objc_getClass("BWNodeConnection")) {
		%init(DaemonDiag);
		DiagLog(@"graph hooks installed");
	} else {
		DiagLog(@"BWGraph/BWNodeConnection not loaded yet");
	}
}
#endif

#pragma mark - Daemon side: AVCaptureSession.plist / CameraSetup.plist

static id MutableDeepCopy(id obj) {
	if ([obj isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:[obj count]];
		[(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) { m[k] = MutableDeepCopy(v); }];
		return m;
	}
	if ([obj isKindOfClass:[NSArray class]]) {
		NSMutableArray *m = [NSMutableArray arrayWithCapacity:[obj count]];
		for (id v in (NSArray *)obj) [m addObject:MutableDeepCopy(v)];
		return m;
	}
	return obj;
}

static NSMutableDictionary *Dict(id obj) {
	return [obj isKindOfClass:[NSMutableDictionary class]] ? obj : nil;
}

static NSMutableDictionary *FormatsOf(NSMutableDictionary *device) {
	return Dict(Dict(device[@"MultiStream"])[@"AVCaptureDeviceFormats"]);
}

static NSMutableDictionary *DeviceWithUniqueIDSuffix(NSMutableArray *devices, NSString *suffix) {
	for (id d in devices) {
		NSString *uid = Dict(d)[@"uniqueID"];
		if ([uid isKindOfClass:[NSString class]] && [uid hasSuffix:suffix]) return d;
	}
	return nil;
}

#if defined(EXP_LOWLIGHT) || defined(EXP_STEREO) || defined(EXP_LIGHTINGPREVIEW)
static void PatchExperiments(NSMutableArray *devices);
#endif

static void PatchCaptureSession(NSMutableDictionary *plist) {
	NSMutableArray *devices = plist[@"AVCaptureDevices"];
	if (![devices isKindOfClass:[NSMutableArray class]]) return;
	NSMutableDictionary *wide = DeviceWithUniqueIDSuffix(devices, @"built-in_video:0"); // Back Camera
	NSMutableDictionary *dual = DeviceWithUniqueIDSuffix(devices, @"built-in_video:3"); // Back Dual Camera
	NSMutableDictionary *wideFormats = FormatsOf(wide);

	// iPhone 7 / 7 Plus: un-hide 4K60 and 1080p240 ("Experimental" formats are hidden
	// from apps). The maintainer's working iOS 15 plists also dropped
	// SecondaryScalerUnavailable from these two formats.
	if (IsA10iPhone()) {
		NSMutableDictionary *dualOverrides = FormatsOf(dual);
		for (NSString *name in @[@"UHD60", @"1080p240"]) {
			NSMutableDictionary *f = Dict(wideFormats[name]);
			if (f[@"Experimental"] || f[@"SecondaryScalerUnavailable"]) {
				[f removeObjectsForKeys:@[@"Experimental", @"SecondaryScalerUnavailable"]];
				LOG("un-hid back camera format %{public}@", name);
			}
			// 7 Plus: the dual camera's formats are overrides on top of the wide camera's, so it
			// would inherit the un-hidden formats too. Both sensors can't run 4K60/240 at once;
			// keep them hidden on the dual camera, as the X does, so Camera uses the wide camera.
			if (dualOverrides) {
				NSMutableDictionary *d = Dict(dualOverrides[name]);
				if (!d) { d = [NSMutableDictionary dictionary]; dualOverrides[name] = d; }
				d[@"Experimental"] = @YES;
			}
		}
	}

#ifdef EXP_OVERCAPTURE
	// View Outside the Frame on dual-camera phones. On the 11 Pro this is declared on
	// the multi-camera devices' 12MP and 1080p30 formats, plus
	// ConfigureForSpatialOverCaptureSupport on the main camera's 1080p30.
	NSMutableDictionary *dualFormats = FormatsOf(dual);
	if (wideFormats && dualFormats) {
		Dict(wideFormats[@"1080p30"])[@"ConfigureForSpatialOverCaptureSupport"] = @YES;
		for (NSString *name in @[@"12MP", @"1080p30"]) {
			NSMutableDictionary *f = Dict(dualFormats[name]);
			if (!f) {
				f = [NSMutableDictionary dictionary];
				id depth = Dict(dualFormats[@"720p30"])[@"SupportedDepthDataFormats"];
				if (depth) f[@"SupportedDepthDataFormats"] = depth;
				dualFormats[name] = f;
			}
			f[@"SpatialOverCaptureSupported"] = @YES;
		}
		LOG("added View Outside the Frame keys to the dual camera");
	}
#endif
#if defined(EXP_LOWLIGHT) || defined(EXP_STEREO) || defined(EXP_LIGHTINGPREVIEW)
	PatchExperiments(devices);
#endif
}

#if defined(EXP_LOWLIGHT) || defined(EXP_STEREO) || defined(EXP_LIGHTINGPREVIEW)
static void PatchExperiments(NSMutableArray *devices) {
#ifdef EXP_LOWLIGHT
	// Auto low-light FPS: the 11 Pro declares these on its 30 fps video formats, with a
	// low-light gain cap 256/96 = 2.67x its normal AEMaxGain. Use the same ratio here.
	for (NSString *suffix in @[@"built-in_video:0", @"built-in_video:3"]) {
		NSMutableDictionary *dev = DeviceWithUniqueIDSuffix(devices, suffix);
		NSMutableDictionary *formats = FormatsOf(dev);
		NSMutableDictionary *wideFormats = FormatsOf(DeviceWithUniqueIDSuffix(devices, @"built-in_video:0"));
		double base = [Dict(wideFormats[@"Common"])[@"AEMaxGain"] doubleValue];
		if (!formats || base <= 0) continue;
		for (NSString *name in @[@"720p30", @"1080p30", @"UHD30", @"4k30"]) {
			NSMutableDictionary *f = Dict(formats[name]);
			if (!f) continue;
			f[@"LowLightVideoCaptureSupported"] = @YES;
			f[@"LowLightVideoAEMaxGain"] = @(round(base * 256.0 / 96.0));
		}
	}
	LOG("experiment: low-light video keys added");
#endif
#ifdef EXP_STEREO
	NSMutableDictionary *mic = DeviceWithUniqueIDSuffix(devices, @"built-in_audio:0");
	if (mic && !IsA10OrOlder()) { mic[@"stereoAudioCaptureSupported"] = @YES; LOG("experiment: stereo audio key added"); }
#endif
#ifdef EXP_LIGHTINGPREVIEW
	// Portrait devices: the dual camera's 12MP and the TrueDepth camera's 7MP/12MP formats.
	for (NSString *suffix in @[@"built-in_video:3", @"built-in_video:4"]) {
		NSMutableDictionary *formats = FormatsOf(DeviceWithUniqueIDSuffix(devices, suffix));
		for (NSString *name in @[@"12MP", @"7MP"]) {
			NSMutableDictionary *f = Dict(formats[name]);
			if (!f) continue;
			f[@"StudioAndContourPreviewRenderingSupported"] = @YES;
			f[@"StagePreviewRenderingSupported"] = @YES;
		}
	}
	LOG("experiment: lighting preview keys added");
#endif
}
#endif


static void PatchCameraSetup(NSMutableDictionary *plist) {
	// Depth Control and Portrait Lighting strength are tuning parameters. On the
	// iPhone X the synthetic lens model (SLM) has a 0-0 aperture range and there are
	// no PortraitLightingParameters; the 11 Pro uses f/1.4-f/16 and 0-1.
	NSMutableDictionary *tuning = Dict(plist[@"TuningParameters"]);
	[tuning enumerateKeysAndObjectsUsingBlock:^(NSString *port, id portDict, BOOL *stop) {
		if (![port hasPrefix:@"PortType"] || !Dict(portDict)) return;
		[(NSDictionary *)portDict enumerateKeysAndObjectsUsingBlock:^(id sensorID, id sensor, BOOL *stop2) {
			NSMutableDictionary *sdof = Dict(Dict(sensor)[@"SDOFRenderingParameters"]);
			if (!sdof) return;
			NSMutableDictionary *slm = Dict(sdof[@"SLM"]);
			if (slm && [slm[@"maximumSimulatedAperture"] doubleValue] <= 0) {
				slm[@"minimumSimulatedAperture"] = @1.4;
				slm[@"maximumSimulatedAperture"] = @16.0;
				if ([slm[@"simulatedAperture"] doubleValue] <= 0) slm[@"simulatedAperture"] = @4.5;
				LOG("enabled simulated aperture range for %{public}@ %{public}@", port, sensorID);
			}
			if (!Dict(sensor)[@"PortraitLightingParameters"]) {
				Dict(sensor)[@"PortraitLightingParameters"] = [@{ @"minEffectStrength": @0.0, @"maxEffectStrength": @1.0, @"effectStrength": @0.5 } mutableCopy];
				LOG("added portrait lighting strength for %{public}@ %{public}@", port, sensorID);
			}
		}];
	}];
}

// Takes ownership of `pl` (+1) and returns a +1 object.
static CFPropertyListRef PatchedPlist(CFStringRef name, CFPropertyListRef pl) {
	if (!pl || !name) return pl;
	BOOL session = CFEqual(name, CFSTR("AVCaptureSession.plist"));
	BOOL setup = CFEqual(name, CFSTR("CameraSetup.plist"));
	if (!session && !setup) return pl;
	@try {
		id copy = MutableDeepCopy((__bridge id)pl);
		if (![copy isKindOfClass:[NSMutableDictionary class]]) return pl;
		if (session) PatchCaptureSession(copy); else PatchCameraSetup(copy);
		CFRelease(pl);
		return CFBridgingRetain(copy);
	} @catch (NSException *e) {
		LOG("patching %{public}@ failed: %{public}@", (__bridge NSString *)name, e);
		return pl;
	}
}

static CFPropertyListRef (*orig_FigCaptureCFCreatePropertyList)(CFStringRef name);
static CFPropertyListRef hook_FigCaptureCFCreatePropertyList(CFStringRef name) {
	return PatchedPlist(name, orig_FigCaptureCFCreatePropertyList(name));
}

static CFPropertyListRef (*orig_FigCaptureCFCreatePropertyListForModel)(CFStringRef name, CFStringRef model, int flags);
static CFPropertyListRef hook_FigCaptureCFCreatePropertyListForModel(CFStringRef name, CFStringRef model, int flags) {
	return PatchedPlist(name, orig_FigCaptureCFCreatePropertyListForModel(name, model, flags));
}

#pragma mark - Daemon side: preview stitcher input format on A10 and older

// With QuickTake on, CameraUI uses AVSpatialOverCaptureVideoPreviewLayer (the 4:3/16:9/1:1
// crop preview), so mediaserverd puts a BWPreviewStitcherNode in the preview branch. That node
// takes 420v/420f/x420/x422/p422 only. On A10 and older, HD video (FES, cinematic stabilisation)
// runs the ISP-strip VIS, which needs the camera to deliver packed 4:2:2 'yuvs'. The preview and
// movie branches share that buffer through a pass-through fan-out, so no common format exists,
// -[BWNodeConnection resolveCommonBufferFormat] fails and -[BWGraph _resolveFormats:] returns
// -666. Apple never ships this pairing (their A11+ VIS pipelines deliver 4:2:0).
// Fix: give the stitcher what it takes by putting a pixel-transfer node (the same converter
// Apple uses elsewhere in these graphs) in front of it, with no fixed output format. It passes buffers
// straight through when they're already acceptable, so photo, 4K and everything else that
// already worked is unchanged.

@interface BWPixelTransferNode : NSObject
@end

%group DaemonGraph
%hook BWGraph
- (BOOL)connectOutput:(id)output toInput:(id)input pipelineStage:(id)stage {
	id toNode = V(input, @"node");
	Class stitcher = objc_getClass("BWPreviewStitcherNode"), transfer = objc_getClass("BWPixelTransferNode");
	if (IsA10OrOlder() && stitcher && transfer && [toNode isKindOfClass:stitcher] && ![V(output, @"node") isKindOfClass:transfer]) {
		id conv = [[transfer alloc] init];
		NSError *err = nil;
		// No fixed output format: the converter's output agrees a format with the stitcher (one of
		// its 4:2:0/x422 formats) and its input with the camera. When those already match (photo
		// mode delivers 420f) it passes buffers straight through; only HD's 'yuvs' gets converted.
		if ([conv respondsToSelector:@selector(setPassesBuffersThroughWhenPossible:)])
			((void (*)(id, SEL, BOOL))objc_msgSend)(conv, @selector(setPassesBuffersThroughWhenPossible:), YES);
		((void (*)(id, SEL, id))objc_msgSend)(conv, @selector(setName:), @"11Cam Preview Stitcher Format Converter");
		BOOL added = conv && ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(self, @selector(addNode:error:), conv, &err);
		if (added) {
			BOOL ok = [self connectOutput:output toInput:V(conv, @"input") pipelineStage:stage] &&
			          [self connectOutput:V(conv, @"output") toInput:input pipelineStage:stage];
			LOG("inserted format converter before the preview stitcher: %d", ok);
#ifdef DIAG_LOG
			DiagLog(@"inserted format converter before the preview stitcher: %d", ok);
#endif
			return ok;
		}
		LOG("couldn't add preview converter: %{public}@", err);
#ifdef DIAG_LOG
		DiagLog(@"couldn't add preview converter: %@", err);
#endif
	}
	BOOL ok = %orig;
#ifdef DIAG_LOG
	NSMutableArray *outputs = objc_getAssociatedObject(self, kGraphOutputs);
	if (!outputs) { outputs = [NSMutableArray array]; objc_setAssociatedObject(self, kGraphOutputs, outputs, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
	if (output) [outputs addObject:output];
	if (!ok) DiagLog(@"connectOutput FAILED:\n%@%@", DescribePort(output, @"from"), DescribePort(input, @"to  "));
#endif
	return ok;
}
%end
%end


// Stereo audio: the microphone source switches to 2 channels, but the movie file's audio
// settings (from the Camera app) still ask the AAC encoder for 1 channel, so the file ends up
// mono. When stereo capture was requested, ask the encoder for 2 channels with a stereo layout.
static BOOL sStereoRequested;
%group StereoDaemon
%hook FigAudioCaptureConnectionConfiguration
- (void)setBuiltInMicrophoneStereoAudioCaptureEnabled:(BOOL)e {
	sStereoRequested = e;
	%orig;
}
%end
%hook FigCaptureMovieFileRecordingSettings
- (void)setAudioSettings:(NSDictionary *)settings {
	NSDictionary *use = settings;
	if (sStereoRequested && [settings isKindOfClass:[NSDictionary class]] && [settings[AVNumberOfChannelsKey] intValue] == 1) {
		NSMutableDictionary *m = [settings mutableCopy];
		m[AVNumberOfChannelsKey] = @2;
		AudioChannelLayout layout = { .mChannelLayoutTag = kAudioChannelLayoutTag_Stereo };
		m[AVChannelLayoutKey] = [NSData dataWithBytes:&layout length:sizeof(layout)];
		if ([m[AVEncoderBitRateKey] intValue] > 0 && [m[AVEncoderBitRateKey] intValue] < 128000) m[AVEncoderBitRateKey] = @([m[AVEncoderBitRateKey] intValue] * 2);
		use = m;
		LOG("stereo: movie audio settings 1 -> 2 channels");
	}
#ifdef DIAG_LOG
	DiagLog(@"EXP stereo: movie audio settings from client %@ -> using %@ (stereo requested %d)",
	        [[settings description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "],
	        use == settings ? @"unchanged" : [[use description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "], sStereoRequested);
#endif
	%orig(use);
}
%end
%end

static BOOL sDaemonHooked;

static void HookDaemonIfReady(void) {
	if (sDaemonHooked) return;
	void *create = dlsym(RTLD_DEFAULT, "FigCaptureCFCreatePropertyList");
	void *createForModel = dlsym(RTLD_DEFAULT, "FigCaptureCFCreatePropertyListForModel");
	if (!create && !createForModel) return;
	sDaemonHooked = YES;
	if (create) MSHookFunction(create, (void *)hook_FigCaptureCFCreatePropertyList, (void **)&orig_FigCaptureCFCreatePropertyList);
	if (createForModel) MSHookFunction(createForModel, (void *)hook_FigCaptureCFCreatePropertyListForModel, (void **)&orig_FigCaptureCFCreatePropertyListForModel);
	LOG("daemon hooks installed (%d/%d)", create != NULL, createForModel != NULL);
	if (IsA10OrOlder() && objc_getClass("BWGraph")) %init(DaemonGraph);
#ifdef EXP_STEREO
	const BOOL stereo = YES;
#else
	const BOOL stereo = NO;
#endif
	if (stereo && !IsA10OrOlder() && objc_getClass("FigCaptureMovieFileRecordingSettings")) %init(StereoDaemon);
#ifdef DIAG_LOG
	DaemonDiagInstall();
#endif
}

static void DaemonImageAdded(const struct mach_header *mh, intptr_t slide) {
	HookDaemonIfReady();
}

static void ClearCaptureSourceCache(void) {
	// The daemon reuses its parsed AVCaptureSession.plist from here while the model,
	// build and attribute version are unchanged, which would skip our patch.
	CFPreferencesSetValue(CFSTR("CaptureSourceInfo"), NULL, CFSTR("com.apple.cameracapture.volatile"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSynchronize(CFSTR("com.apple.cameracapture.volatile"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

#pragma mark -

%ctor {
	@autoreleasepool {
		NSString *process = [[NSProcessInfo processInfo] processName];
		if ([process isEqualToString:@"mediaserverd"] || [process isEqualToString:@"cameracaptured"]) {
			ClearCaptureSourceCache();
			HookDaemonIfReady();
			if (!sDaemonHooked) _dyld_register_func_for_add_image(DaemonImageAdded);
		} else {
			sAlwaysOverride = [process isEqualToString:@"Preferences"];
			HookClientIfReady();
			if (!sClientHooked || !sGestaltHooked) _dyld_register_func_for_add_image(ClientImageAdded);
		}
	}
}
