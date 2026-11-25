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
//    initializer AVGestalt is untouched, so AVFoundation's own behaviour is Apple's.
//
// 2. Camera daemon (mediaserverd)
//    The daemon reads <model>/AVCaptureSession.plist and <model>/CameraSetup.plist
//    through FigCaptureCFCreatePropertyList / ...ForModel. We patch the returned
//    dictionaries in memory (no files are replaced). The daemon caches its parsed
//    AVCaptureSession.plist in com.apple.cameracapture.volatile -> CaptureSourceInfo,
//    so that cache is cleared at daemon start, otherwise the plist is never re-read.
//
// Deliberately NOT enabled: responsive shutter, capture-on-touch-down, deferred
// processing, Deep Fusion, Photographic Styles. The daemon formats on A9-A11 phones
// don't declare support for them, and turning them on in the UI only would make
// the Camera app ask for captures the daemon can't deliver.

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

static BOOL HasDualBackCamera(void) {
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
#ifndef NO_QUICKTAKE // diagnostic build: `make package NOQUICKTAKE=1`
		o[@"AVGQDeviceSupportsMomentCapture"] = @YES;
		// Exposure slider (needs the CTM UI above).
		o[@"AVGQDeviceSupportsExposureBiasWithoutExposureLock"] = @YES;
#endif
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

		// View Outside the Frame, only on dual-camera phones; the daemon side adds the
		// matching format keys (see PatchCaptureSession).
		if (HasDualBackCamera()) o[@"AVGQDeviceSupportsSpatialOverCapture"] = @YES;

		// ---- Experiments (`make package EXP="LOWLIGHT STEREO LIGHTINGPREVIEW MODERNHDR LIVETEXT"`) ----
#ifdef EXP_LOWLIGHT
		// Auto low-light FPS for 30 fps video (Settings > Camera > Record Video). The daemon
		// side adds LowLightVideoCaptureSupported/LowLightVideoAEMaxGain to the formats.
		o[@"AVGQDeviceSupportsAutoLowLightVideo"] = @YES;
#endif
#ifdef EXP_STEREO
		// Stereo audio in video (XR and later). The daemon side marks the microphone as
		// stereo-capable; Apple's dev switch is CAMFeatureDevelopmentAllowStereoAudioRecording.
		o[@"AVGQDeviceSupportsStereoAudioRecording"] = @YES;
#endif
#ifdef EXP_MODERNHDR
		// "Modern" HDR (iPhone 8/X): HDR done in the GNR fusion step, with the Auto HDR switch
		// in Settings. The daemon side marks the iPhone 7's photo formats GNRHDRSupported and
		// gives its sensor the X's local-tone-mapping HDR tuning.
		if (IsA10iPhone()) o[@"AVGQCameraHDR2Capability"] = @YES;
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
#ifdef EXP_MODERNHDR
			o[@"AVGQCameraHDRVersion"] = @2;
#endif
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

#ifdef EXP_LIVETEXT
// Live Text. CameraUI shows the Live Text button from AVGQHasAppleNeuralEngine (above), but
// VisionKit makes its own decision once per process, in a private dispatch_once that checks for
// a Neural Engine, and caches the answer in a private global. +[VKImageAnalyzer
// deviceSupportsImageAnalysis] is a single branch to vk_imageAnalysisSupportedAndSettingsSwitchEnabled,
// whose first byte-load (adrp + ldrb) reads that cached global. After the once has run, set it to YES.
// Text recognition itself then runs without the Neural Engine (VisionKit's own "no ANE" path).
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
		BOOL after = ((BOOL (*)(id, SEL))objc_msgSend)(analyzer, sel);
		LOG("live text: VisionKit support flag set, deviceSupportsImageAnalysis %d -> %d", before, after);
#ifdef DIAG_LOG
		DiagLog(@"EXP livetext: VisionKit deviceSupportsImageAnalysis %d -> %d (the second value also needs Live Text switched on in Settings > General > Language & Region)", before, after);
#endif
		return;
	}
	LOG("live text: flag not found, leaving it");
}
#endif

%group Capabilities
%hook CAMCaptureCapabilities
- (id)initWithHostProcess:(long long)hostProcess {
	sCapsInitDepth++;
	id me = %orig;
	sCapsInitDepth--;
	// iPhone 11-style zoom dial. CameraUI only enables it with an ultra-wide camera.
	// (Its style, zoomDialStyle, already follows the new UI once QuickTake is on.)
	if (me) SetBoolIvar(me, "_zoomPlatterSupported", YES);
#ifdef EXP_LIVETEXT
	if ([[[NSProcessInfo processInfo] processName] isEqualToString:@"Camera"]) EnableLiveText();
	// Live text detection in the viewfinder needs the Neural Engine, but Live Text on a captured
	// frame works. Keep the Live Text button visible so it can always be tapped (A10 and older).
	if (me && IsA10OrOlder()) SetBoolIvar(me, "_imageAnalysisButtonAlwaysVisible", YES);
#endif
#ifdef EXP_LOWLIGHT
	if (me) SetBoolIvar(me, "_autoLowLightVideoSupported", YES);
#endif
#ifdef EXP_STEREO
	// CameraUI only allows stereo for some host processes; Settings may not be one of them.
	if (me) SetBoolIvar(me, "_stereoAudioRecordingSupported", YES);
#endif
#ifdef DIAG_NO_FORMAT_CONTROL // diagnostic build: in-viewfinder HD/4K + fps switches off
	if (me) SetBoolIvar(me, "_interactiveVideoFormatControlAlwaysEnabled", NO);
#endif
#ifdef DIAG_LOG
	DiagLog(@"CAMCaptureCapabilities initWithHostProcess:%lld", hostProcess);
	if (me) DiagLogCapabilities(me);
#endif
#ifdef DIAG_NO_SHUTTER_ZOOM // diagnostic build: drag-to-zoom shutter off
	if (me) SetBoolIvar(me, "_allowDynamicShutterZoom", NO);
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
// Writes to /var/mobile/Media/11Cam-diag.txt and, as a fallback in case the Camera
// sandbox refuses that, <Camera data container>/Documents/11Cam-diag.txt.
#ifdef NO_QUICKTAKE
#define DIAG_FILE @"11Cam-diag-noquicktake.txt"
#else
#define DIAG_FILE @"11Cam-diag.txt"
#endif
static NSMutableArray<NSString *> *sDiagPaths;   // files we can write
static NSMutableArray<NSString *> *sDiagTried;   // every path tried, with the result
static NSMutableString *sDiagBuffer;             // the whole log, so a late-found location gets everything
static dispatch_queue_t sDiagQueue;

// Try to create `path`; if it works, write the whole log so far and keep appending to it.
static void DiagTryPath(NSString *path) {
	dispatch_async(sDiagQueue, ^{
		if (!path || [sDiagPaths containsObject:path]) return;
		NSError *err = nil;
		BOOL ok = [sDiagBuffer writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:&err];
		[sDiagTried addObject:[NSString stringWithFormat:@"%@=%@", path, ok ? @"ok" : (err.localizedDescription ?: @"failed")]];
		if (ok) [sDiagPaths addObject:path];
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

// Every BOOL / number / string property of obj (all classes up to NSObject).
static NSString *PropertyDump(id obj) {
	if (!obj) return @"";
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	for (Class c = object_getClass(obj); c && c != [NSObject class]; c = class_getSuperclass(c)) {
		unsigned n = 0;
		objc_property_t *props = class_copyPropertyList(c, &n);
		for (unsigned i = 0; i < n; i++) {
			NSString *name = @(property_getName(props[i]));
			if (d[name] || [name hasPrefix:@"_"] || [name isEqualToString:@"description"] || [name isEqualToString:@"debugDescription"] || [name isEqualToString:@"hash"]) continue;
			char *type = property_copyAttributeValue(props[i], "T");
			BOOL simple = type && (strchr("cBiIsSlLqQfd", type[0]) || !strcmp(type, "@\"NSString\"") || !strcmp(type, "@\"NSNumber\""));
			char *getter = property_copyAttributeValue(props[i], "G");
			SEL sel = getter ? sel_registerName(getter) : NSSelectorFromString(name);
			free(type); free(getter);
			if (!simple || ![obj respondsToSelector:sel]) continue;
			id v = SafeValue(obj, name);
			if (v) d[name] = v;
		}
		free(props);
	}
	NSMutableString *s = [NSMutableString string];
	for (NSString *k in [[d allKeys] sortedArrayUsingSelector:@selector(compare:)]) [s appendFormat:@" %@=%@", k, d[k]];
	return s;
}

// Every instance variable of obj (numbers/BOOLs as values, objects as short descriptions).
static NSString *IvarDump(id obj, int depth) {
	if (!obj) return @"";
	NSMutableString *s = [NSMutableString string];
	for (Class c = object_getClass(obj); c && c != [NSObject class]; c = class_getSuperclass(c)) {
		unsigned n = 0;
		Ivar *ivars = class_copyIvarList(c, &n);
		for (unsigned i = 0; i < n; i++) {
			const char *name = ivar_getName(ivars[i]), *type = ivar_getTypeEncoding(ivars[i]);
			if (!name || !type) continue;
			uint8_t *p = (uint8_t *)(__bridge void *)obj + ivar_getOffset(ivars[i]);
			switch (type[0]) {
				case 'c': case 'B': [s appendFormat:@" %s=%d", name, *(int8_t *)p]; break;
				case 'i': case 'I': [s appendFormat:@" %s=%d", name, *(int32_t *)p]; break;
				case 'q': case 'Q': case 'l': case 'L': [s appendFormat:@" %s=%lld", name, *(long long *)p]; break;
				case 'f': [s appendFormat:@" %s=%g", name, *(float *)p]; break;
				case 'd': [s appendFormat:@" %s=%g", name, *(double *)p]; break;
				case '@': {
					id v = object_getIvar(obj, ivars[i]);
					if (!v) break;
					NSString *cls = NSStringFromClass([v class]);
					// Recurse one level into AVFoundation's private "internal" objects.
					if (depth == 0 && [cls hasSuffix:@"Internal"]) { [s appendFormat:@"\n      [%s %@]%@", name, cls, IvarDump(v, 1)]; break; }
					NSString *desc = nil;
					if ([v isKindOfClass:[NSNumber class]] || [v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSArray class]] || [v isKindOfClass:[NSDictionary class]] || [v isKindOfClass:[NSSet class]])
						desc = [[[v description] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
					else desc = cls;
					if (desc.length > 400) desc = [[desc substringToIndex:400] stringByAppendingString:@"..."];
					[s appendFormat:@" %s=%@", name, desc];
					break;
				}
				default: break;
			}
		}
		free(ivars);
	}
	return s;
}

static NSString *SessionSnapshot(id session) {
	NSMutableString *s = [NSMutableString string];
	[s appendFormat:@"preset=%@ running=%@ interrupted=%@", SafeValue(session, @"sessionPreset"), SafeValue(session, @"running"), SafeValue(session, @"interrupted")];
	for (id input in SafeValue(session, @"inputs") ?: @[]) {
		id dev = SafeValue(input, @"device");
		if (!dev) { [s appendFormat:@"\n    input %@", NSStringFromClass([input class])]; continue; }
		[s appendFormat:@"\n    input %@ activeFormat=%@ minFrameDuration=%@ maxFrameDuration=%@ stabilization? zoom=%@",
			SafeValue(dev, @"localizedName"), SafeValue(dev, @"activeFormat"),
			SafeValue(dev, @"activeVideoMinFrameDuration"), SafeValue(dev, @"activeVideoMaxFrameDuration"),
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
	                       @"_captureOnTouchDown", @"_autoLowLightVideoSupported", @"_stereoAudioRecordingSupported", @"_livePhotoAutoModeSupported",
	                       @"_backLiveStageLightSupported", @"_frontLiveStageLightSupported", @"_imageAnalysisSupported", @"_imageAnalysisButtonAlwaysVisible", @"_backHDRSupported", @"_backAutomaticHDRSupported", @"_modernHDRSupported", @"_HDRSettingAllowed",
	                       @"_livePhotoAutoModeSupported", @"_imageAnalysisSupported", @"_sfCameraFontSupported", @"_zoomPlatterSupported",
	                       @"_responsiveShutterSupported", @"_shotBufferSupported", @"_back4k60VideoSupported", @"_back1080p240Supported"]) {
		Ivar v = class_getInstanceVariable(object_getClass(caps), iv.UTF8String);
		if (v) [s appendFormat:@" %@=%d", [iv substringFromIndex:1], *(BOOL *)((uint8_t *)(__bridge void *)caps + ivar_getOffset(v))];
	}
	DiagLog(@"%@", s);
}

%group Diag
@interface VKCaptureTextAnalysisRequest : NSObject
@end
// Experiment checks: Live Text.
%hook VKCaptureTextAnalysisRequest
- (id)initWithImage:(id)image focusQuad:(id)quad delegate:(id)delegate {
	DiagLog(@"EXP livetext: Camera started a text analysis request (delegate %@)", NSStringFromClass([delegate class]));
	return %orig;
}
%end
%hook CAMViewfinderViewController
- (BOOL)_shouldShowImageAnalysisButtonForGraphConfiguration:(id)configuration {
	BOOL r = %orig;
	DiagLog(@"EXP livetext: show Live Text button = %d", r);
	return r;
}
- (void)_updateTextAnalysisWithInsert:(id)insert instructions:(BOOL)instructions animated:(BOOL)animated {
	DiagLog(@"EXP livetext: text detection result %@", insert ? @"FOUND TEXT" : @"none");
	%orig;
}
%end
%hook AVCaptureSession
- (void)commitConfiguration {
	%orig;
	NSMutableString *dump = [NSMutableString stringWithFormat:@"commitConfiguration: %@\n  SESSION%@", SessionSnapshot(self), PropertyDump(self)];
	for (id input in SafeValue(self, @"inputs") ?: @[]) {
		id dev = SafeValue(input, @"device");
		[dump appendFormat:@"\n  INPUT %@%@", NSStringFromClass([input class]), PropertyDump(input)];
		if (dev) [dump appendFormat:@"\n  DEVICE %@%@", SafeValue(dev, @"localizedName"), PropertyDump(dev)];
	}
	for (id output in SafeValue(self, @"outputs") ?: @[]) {
		[dump appendFormat:@"\n  OUTPUT %@%@", NSStringFromClass([output class]), PropertyDump(output)];
		for (id conn in SafeValue(output, @"connections") ?: @[]) [dump appendFormat:@"\n    CONNECTION%@", PropertyDump(conn)];
	}
	NSString *preset = SafeValue(self, @"sessionPreset");
	if ([preset isEqualToString:@"AVCaptureSessionPresetHigh"] || [preset isEqualToString:@"AVCaptureSessionPresetHigh60"] || [preset isEqualToString:@"AVCaptureSessionPreset1920x1080"]) {
		for (id output in SafeValue(self, @"outputs") ?: @[]) {
			[dump appendFormat:@"\n  PRIVATE %@%@", NSStringFromClass([output class]), IvarDump(output, 0)];
			if ([output respondsToSelector:NSSelectorFromString(@"metadataObjectTypes")]) [dump appendFormat:@"\n  METADATA TYPES %@", SafeValue(output, @"metadataObjectTypes")];
			if ([output respondsToSelector:NSSelectorFromString(@"preparedPhotoSettingsArray")]) [dump appendFormat:@"\n  PREPARED %@", SafeValue(output, @"preparedPhotoSettingsArray")];
			if ([output respondsToSelector:NSSelectorFromString(@"photoSettingsForSceneMonitoring")]) [dump appendFormat:@"\n  SCENE MONITORING %@", IvarDump(SafeValue(output, @"photoSettingsForSceneMonitoring"), 0)];
			if ([output respondsToSelector:NSSelectorFromString(@"isDigitalFlashCaptureEnabled")]) [dump appendFormat:@"\n  DIGITAL FLASH ENABLED %@", SafeValue(output, @"digitalFlashCaptureEnabled")];
			if ([output respondsToSelector:@selector(outputSettingsForConnection:)]) {
				for (id conn in SafeValue(output, @"connections") ?: @[]) {
					@try { [dump appendFormat:@"\n  MOVIE SETTINGS %@", ((id (*)(id, SEL, id))objc_msgSend)(output, @selector(outputSettingsForConnection:), conn)]; } @catch (NSException *e) {}
				}
			}
		}
		for (id input in SafeValue(self, @"inputs") ?: @[]) {
			id dev = SafeValue(input, @"device");
			if (dev) [dump appendFormat:@"\n  PRIVATE DEVICE %@%@", SafeValue(dev, @"localizedName"), IvarDump(dev, 0)];
		}
		[dump appendFormat:@"\n  PRIVATE SESSION%@", IvarDump(self, 0)];
		// Every connection in the session, including the viewfinder's preview layer.
		int i = 0;
		for (id conn in SafeValue(self, @"connections") ?: @[]) {
			i++;
			[dump appendFormat:@"\n  SESSIONCONN %d%@\n    PRIVATECONN%@", i, PropertyDump(conn), IvarDump(conn, 0)];
			id layer = SafeValue(conn, @"videoPreviewLayer");
			if (layer) [dump appendFormat:@"\n  PREVIEWLAYER %d%@\n    PRIVATELAYER%@", i, PropertyDump(layer), IvarDump(layer, 0)];
		}
	}
	DiagLog(@"%@", [[dump componentsSeparatedByString:@"\n"] componentsJoinedByString:@"\n"]);
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

%hook AVCapturePhotoOutput
- (void)setPhotoSettingsForSceneMonitoring:(id)settings {
	DiagLog(@"setPhotoSettingsForSceneMonitoring: %@", settings);
	%orig;
}
- (void)setDigitalFlashMode:(long long)mode {
	DiagLog(@"photoOutput setDigitalFlashMode:%lld", mode);
	%orig;
}
%end

%hook AVCaptureMovieFileOutput
- (void)startRecordingToOutputFileURL:(NSURL *)url recordingDelegate:(id)delegate {
	DiagLog(@"movie startRecording: %@", url.path);
	DiagTryPath([[url.path stringByDeletingLastPathComponent] stringByAppendingPathComponent:DIAG_FILE]);
	dispatch_async(sDiagQueue, ^{ DiagLog(@"log locations tried: %@", [sDiagTried componentsJoinedByString:@" | "]); });
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
		NSString *home = NSHomeDirectory();
		DiagStart_(DIAG_FILE, @[@"/var/mobile/Media", [home stringByAppendingPathComponent:@"Documents"], NSTemporaryDirectory(),
		                        [home stringByAppendingPathComponent:@"Library/Caches"], @"/var/mobile/Library/Caches/com.apple.camera",
		                        @"/var/mobile/Media/PhotoData", @"/var/mobile/Media/DCIM", @"/var/tmp"]);
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
%hook BWStreamingFilterNode
- (void)setStudioAndContourRenderingEnabled:(BOOL)e { DiagLog(@"EXP lightingpreview: live Studio/Contour rendering = %d", e); %orig; }
- (void)setStageRenderingEnabled:(BOOL)e { DiagLog(@"EXP lightingpreview: live Stage rendering = %d", e); %orig; }
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
#if defined(EXP_LOWLIGHT) || defined(EXP_STEREO) || defined(EXP_LIGHTINGPREVIEW)
	PatchExperiments(devices);
#endif
#ifdef EXP_MODERNHDR
	if (IsA10iPhone()) {
		for (NSString *name in @[@"12MP", @"Square"]) Dict(wideFormats[name])[@"GNRHDRSupported"] = @YES;
		LOG("experiment: GNR HDR on the back camera's photo formats");
	}
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
	if (mic) { mic[@"stereoAudioCaptureSupported"] = @YES; LOG("experiment: stereo audio key added"); }
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

#ifdef EXP_MODERNHDR
// iPhone X back camera (sensor 0x0343) GNR LTMHDRParameters {Fusion, NoiseModel}, from iOS 16.7.16 CameraSetup.plist.
static NSString *const kXLTMHDRParameters = @"YnBsaXN0MDDSAQIDeVZGdXNpb25aTm9pc2VNb2RlbNwEBQYHCAkKCwwNDg8Qb3BxcnN0dXZ3d3hVQmFuZHNfEB1CbGFja1N1YnRyYWN0aW9uQ2xpcHBpbmdSYXRpb18QGEJsYWNrU3VidHJhY3Rpb25Mb3dMaW1pdF8QFkRldGFpbEVuaGFuY2VMZWZ0TGltaXRfEBdEZXRhaWxFbmhhbmNlUmlnaHRMaW1pdF8QFURldGFpbEVuaGFuY2VTdHJlbmd0aF8QFEVWUENocm9tYVdlaWdodEJvb3N0XxATRml4UHlyYW1pZEFsaWdubWVudF8QEkdyYXlHaG9zdGluZ0N1dG9mZl8QJUdyYXlHaG9zdGluZ0VWMEVWTURpZmZlcmVuY2VUaHJlc2hvbGRfEB5HcmF5R2hvc3RpbmdFVjBXZWlnaHRUaHJlc2hvbGRfEBdNYXhpbXVtQ29udHJhc3RTdHJlbmd0aKQRN05f1hITFBUWFxgdIScsMVxBZGFwdGl2ZUJsdXJeQmxhY2tUaHJlc2hvbGRfEBRDaHJvbWFGdXNpb25TdHJlbmd0aFpEaWZmV2VpZ2h0XxASTHVtYUZ1c2lvblN0cmVuZ3RoWlNoYXJwZW5pbmekGRobHCM/7gQYk3S8aiM/7MzMzMzMzSNADgAAAAAAACM/4AAAAAAAAKQeHyAfI0ASwo9cKPXDIz/TMzMzMzMzI0Aiwo9cKPXD0iIjJCZfEBREZW5zZUZyYW1lUGFyYW1ldGVyc18QFVNwYXJzZUZyYW1lUGFyYW1ldGVyc6IlJSM/8AAAAAAAAKIlJdIiIygrpCUpKiUjQAAAAAAAAAAjQBAAAAAAAACkJSkqJdIiIy0vpCUlLiUjQGQAAAAAAACmJTAbMC4wI0AIAAAAAAAAqDIzNDU2NS41Iz/uBBigAAAAIz/0zMy/////I0AiAAAAAAAAIz/xmZmgAAAAI0BCwAAAAAAA1hITFBUWFzg6PUJGTKQZJRs5Iz/pmZmZmZmapiU7PDsuOyM/wzMzMzMzMyNAFAAAAAAAANIiIz4/oiUcpBlAIEEjP+XCj1wo9cMjP+Cj1wo9cKTSIiNDRKQlKSolpBlFICUjQAwAAAAAAADSIiNHSKIlHKYySUpLLksjP+XCj2AAAAAjQCLCj2AAAAAjP+Cj1wAAAACmMk0bJS4lIz/wzMy/////1hITFBUWF09QUVZZXKQZJRsapiU7PDsuO9IiI1JToiUcpBlUIFUjP+BR64UeuFIjP9j1wo9cKPbSIiNXWKQlKSolpBlFICXSIiNaW6IlHKQZVCBVpBldG14jP/GZmZmZmZojP/DMzMzMzM3WEhMUFRYXYGFjaGtuoiUlpiViPGIuYiM/uZmZmZmZmtIiI2RloiUfpBlmIGcjP9XCj1wo9cMjP9Cj1wo9cKTSIiNpaqIlJaQZRSAl0iIjbG2iJRykGWYgZ6IlJSM/UGJN0vGp/CM/uFHrhR64UiM/yZmZmZmZmiM/1mZmZmZmZhADIwAAAAAAAAAACSM/Cjbi6xxDLSM/0AAAAAAAABAB3Xp7BHx9fn+AgYKDhIWGPIcp19103+DhvSnlW0JhbmRGYWN0b3JDW0JhbmRGYWN0b3JZWkJpYXNGYWN0b3JaQmx1ZW5lc3NDYlpCbHVlbmVzc0NyXxAVQ2hyb21hRGVtb2lyZVN0cmVuZ3RoVkdhbW1hQ1ZHYW1tYVlfEBFIaWdoR2FpblRocmVzaG9sZF8QF0xlbnNTaGFkaW5nRmFjdG9yQ2hyb21hXxAVTGVuc1NoYWRpbmdGYWN0b3JMdW1hW1Nsb3BlRmFjdG9yI0AeAAAAAAAApIigs8bXiYqLjI2Oj5CVl5ibnp9fEBVDaHJvbWFEZW5vaXNlU3RyZW5ndGhfEBFGbGF0bmVzc1RocmVzaG9sZF8QD0hhbG9TdXBwcmVzc2lvbl8QE0x1bWFEZW5vaXNlU3RyZW5ndGhfEA9MdW1hUmVtaXhXZWlnaHRfEBNSYWRpYWxGbGF0bmVzc0Jvb3N0XxAUUmFkaWFsU2hhcnBuZXNzQm9vc3TSkZKTlF8QEkVWTUZyYW1lUGFyYW1ldGVyc18QFW5vbkVWTUZyYW1lUGFyYW1ldGVyc6IlJaIlJaIlliNABAAAAAAAAKIlKtKRkpmaoiUloiUl0pGSnJ2iJSWmJSUpJS4loiV0oiUf2aGJooqLjI2Oj6Okp6ipqq6xsllCbHVlQm9vc3RdRmxhdG5lc3NCb29zdKQlMBt00pGSpaaiJSmiJSWmJSUqdC50oiUloiUq0pGSq62kJawurCNAGAAAAAAAAKQlJS4l0pGSr7CkJSUuJaYlJSklLiWiJXSiJR/ZoYmiiouMjY6PtLW4ubq7wcTFpCUwG3TSkZK2t6IlKaIlKaYlJSp0LnSiJSWiJXTSkZK8wKYlvSm9vr8QAlMxNjBRMaIlYtKRksLDpCUlLiWmJSUwJS4loiV0oiUf2aGJooqLjI2Oj8fIzM3Oz9LV1qQlMBt00pGSycukJSnKyhAFonjKpiUlKnQudKIlJaIldNKRktDRpCUlKSWiJWLSkZLT1KIlJaIlJaIldKIlH9PY2dol29xTZW5kVm1hcmdpblVzdGFydCM/qZmZmZmZmiM/5MzMzMzMzdPY2dp03nQjP+MzMzMzMzMjP8mZmZ////8jP+KPXCAAAACk4jzj5CNAIOFHrhR64SNAJJmZmZmZmiNAHAAAAAAAACNAPgAAAAAAAAAIAA0AFAAfADgAPgBeAHkAkgCsAMQA2wDxAQYBLgFPAWkBbgF7AYgBlwGuAbkBzgHZAd4B5wHwAfkCAgIHAhACGQIiAicCPgJWAlkCYgJlAmoCbwJ4AoEChgKLApACmQKgAqkCsgK7AsQCzQLWAt8C7ALxAvoDAQMKAxMDGAMbAyADKQMyAzcDPANBA0oDTwNSA1kDYgNrA3QDewOEA5EDlgOdA6IDpQOqA7MDvAPBA8YDywPQA9MD2APdA+YD7wP8A/8EBgQPBBQEFwQcBCUELgQzBDYEOwRABEMESARLBFQEXQRmBG8EcQR6BHsEhASNBI8EqgS2BMIEzQTYBOME+wUCBQkFHQU3BU8FWwVkBWkFeAWQBaQFtgXMBd4F9AYLBhAGJQY9BkAGQwZGBk8GUgZXBloGXQZiBmUGbAZvBnIGhQaPBp0GoganBqoGrQa0BrcGuga/BsQGzQbSBtcG3AbjBuYG6Qb8BwEHBgcJBwwHEwcWBxkHHgclBycHKwctBzAHNQc6B0EHRAdHB1oHXwdkB2kHawduB3UHeAd7B4AHhQeIB40HkAeTB5YHmQegB6QHqwexB7oHwwfKB9MH3AflB+oH8wf8CAUAAAAAAAACAQAAAAAAAADmAAAAAAAAAAAAAAAAAAAIDg==";
#endif

static void PatchCameraSetup(NSMutableDictionary *plist) {
	// Depth Control and Portrait Lighting strength are tuning parameters. On the
	// iPhone X the synthetic lens model (SLM) has a 0-0 aperture range and there are
	// no PortraitLightingParameters; the 11 Pro uses f/1.4-f/16 and 0-1.
	NSMutableDictionary *tuning = Dict(plist[@"TuningParameters"]);
#ifdef EXP_MODERNHDR
	if (IsA10iPhone()) {
		NSData *data = [[NSData alloc] initWithBase64EncodedString:kXLTMHDRParameters options:0];
		NSDictionary *ltm = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL] : nil;
		[Dict(tuning[@"PortTypeBack"]) enumerateKeysAndObjectsUsingBlock:^(id sensorID, id sensor, BOOL *stop) {
			NSMutableDictionary *gnr = Dict(Dict(sensor)[@"GNRParameters"]);
			if (!gnr || !ltm) return;
			if (!Dict(gnr[@"Fusion"])[@"LTMHDRParameters"]) Dict(gnr[@"Fusion"])[@"LTMHDRParameters"] = [ltm[@"Fusion"] mutableCopy];
			if (!Dict(gnr[@"NoiseModel"])[@"LTMHDRParameters"]) Dict(gnr[@"NoiseModel"])[@"LTMHDRParameters"] = [ltm[@"NoiseModel"] mutableCopy];
			LOG("experiment: added LTM HDR tuning for back sensor %{public}@", sensorID);
		}];
	}
#endif
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
