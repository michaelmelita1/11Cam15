#import <UIKit/UIKit.h>

%hook CAMCaptureCapabilities
-(BOOL)isModernHDRSupported {
	return YES;
}
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
-(BOOL)isSpatialOverCaptureSupported {
    return YES;
}
-(BOOL)isBackSpatialOverCaptureSupported {
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
-(BOOL)isLowLightSupported {
    return YES;
}
-(BOOL)isBackLowLightSupported {
    return YES;
}
-(BOOL)isCinematicModeSupported {
    return YES;
}
-(BOOL)isBackCinematicModeSupported {
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
-(BOOL)isBackSingleCameraPortraitModeSupported {
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
-(BOOL)isStreamingDisparitySupported {
		return YES;
}
-(BOOL)isStreamingDepthSupported {
		return YES;
}
-(BOOL)isStillImageDisparitySupported {
		return YES;
}
-(BOOL)isStillImageDepthSupported {
		return YES;
}
-(BOOL)isGlobalToneMappingSupported {
		return YES;
}
-(BOOL)isSpatialOverCaptureSupported {
		return YES;
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
		return YES;
}
+(BOOL)isEligibleForBackgroundBlur {
		return YES;
}
-(BOOL)isBackgroundBlurActive {
		return YES;
}
-(BOOL)isProResSupported {
		return YES;
}
-(BOOL)isLowLightBoostSupported {
		return YES;
}
-(BOOL)isLowLightBoostEnabled {
		return YES;
}
-(BOOL)automaticallyEnablesLowLightBoostWhenAvailable {
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
