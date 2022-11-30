#import <UIKit/UIKit.h>

%hook CAMCaptureCapabilities
-(BOOL)isNeuralEngineSupported {
    return YES;
}
-(BOOL)isDeepFusionSupported {
    return YES;
}
-(long long) zoomDialStyle {
		return 1;
}
-(bool)isCTMSupported {
    return YES;
}
-(BOOL)isCTMSupportSupressed {
    return NO;
}
-(BOOL)deviceSupportsCTM {
    return YES;
}
-(BOOL)contentAwareDistortionCorrectionSupported {
    return YES;
}
-(BOOL)isSemanticStylesSupported {
    return YES;
}
-(BOOL)enableSemanticDevelopmentFilterDebugging {
    return YES;
}
-(BOOL)isModernHDRSupported {
	return YES;
}
-(BOOL)imagePickerUsesModernLayout {
	return YES;
}
-(BOOL)captureOnTouchDown {
		return YES;
}
-(BOOL)automaticallyEnablesLowLightBoostWhenAvailable {
		return YES;
}
-(BOOL)isLowLightSupported {
    return YES;
}
-(BOOL)portraitZoomSupported {
    return YES;
}
-(BOOL)isZoomPlatterSupported {
    return YES;
}
-(BOOL)isBackLowLightSupported {
    return YES;
}
-(BOOL)isCinematicModeSupported {
    return NO;
}
-(BOOL)responsiveShutterSupported {
    return YES;
}
-(BOOL)isPortraitModeSupported {
    return YES;
}
-(BOOL)isFrontPortraitModeSupported {
    return YES;
}
-(BOOL)isFrontSingleCameraPortraitModeSupported {
    return YES;
}
-(bool)arePortraitEffectsSupported {
		return YES;
}
-(long long)supportedPortraitLightingVersion {	
                return 2;
}
-(bool)_backStageLightPortaitEffectsSupported {
		return YES;
}
-(bool)isBackLiveStageLightSupported {
		return YES;
}
-(bool)isLivePreviewSupportedForLightingType:(long long)arg1 devicePosition:(long long)arg2 {
		return YES;
		arg1 = 1;
		arg2 = 1;
}
-(bool)isLivePhotoAutoModeSupported {
		return YES;
}
-(bool)isDepthEffectApertureSupported {
		return YES;
}
-(bool)isPortraitEffectIntensitySupported {
		return YES;
}
%end
%hook AVCaptureDeviceFormat				//Depth Control and Intensity Control
-(float)minSimulatedAperture {
		return 1.4;
}
-(float)maxSimulatedAperture {
		return 16;
}
-(float)defaultSimulatedAperture {
		return 4.5;
}
-(float)minPortraitLightingEffectStrength {
		return 0;
}
-(float)maxPortraitLightingEffectStrength {
		return 100;
}
-(float)defaultPortraitLightingEffectStrength {
		return 50;
}
-(BOOL)isMultiCamSupported {
		return YES;
}
-(BOOL)isSISSupported {
		return YES;
}
-(BOOL)_isDepthDataDeliveryEnabled {
		return YES;
}
-(BOOL)isCinematicFramingActive {
		return NO;
}
+(BOOL)isEligibleForBackgroundBlur {
		return YES;
}
-(BOOL)isBackgroundBlurActive {
		return YES;
}
-(BOOL)isProResSupported {
		return NO;
}
-(BOOL)isLowLightBoostSupported {
		return YES;
}
-(BOOL)isLowLightBoostEnabled {
		return YES;
}
-(BOOL)isSemanticStyleRenderingSupported {
		return YES;
}
-(BOOL)isGlobalToneMappingSupported {
		return YES;
}
-(BOOL)isHighPhotoQualitySupported {
		return YES;
}
-(BOOL)supportsQuadraHighResolutionStillImageOutput {
		return YES;
}
%end
%hook CAMViewfinderViewController 
-(BOOL)_shouldUseZoomControlInsteadOfSlider {
    return YES;
}
%end
%hook AVApplePortraitMetadata 
-(BOOL)supportsSecureCoding {
    return YES;
}
%end

%hook CAMDynamicShutterControl
-(BOOL)_shouldShortPressOnTouchUp {
		return YES;
}
%end

%hook CAMContentAwareDistortionCorrectionCommand
-(BOOL)_isEnabled {
		return YES;
}
%end

%hook CAMLowLightBoostCommand
-(BOOL)_isEnabled {
		return YES;
}
%end

%hook CAMLowLightConfigurationCommand
-(BOOL)_isEnabled {
		return YES;
}
%end

%hook CAMLowLightSlider
-(BOOL)_isPerformingCaptureAnimation {
		return YES;
}
-(BOOL)isLowLightActive {
		return YES;
}
%end

%hook CAMLowLightStatusIndicator
-(BOOL)canShowValue {
		return YES;
}
-(BOOL)shouldUseActiveTintForCurrentState {
		return YES;
}
-(long long)lowLightMode {
		return YES;
}
%end