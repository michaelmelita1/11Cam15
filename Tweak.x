#import <UIKit/UIKit.h>
%hook CAMCaptureCapabilities
-(BOOL)isModernHDRSupported {
	return YES;
}
-(long long) zoomDialStyle {
		return 2;
}
-(bool)isCTMSupported {
    return YES;
}
-(BOOL)isCTMSupportSupressed {
    return NO;
}
-(BOOL)isSemanticStylesSupported {
    return YES;
}
-(BOOL)allowHaptics {
    return YES;
}
-(BOOL)isBackCinematicModeSupported {
    return YES;
}
-(BOOL)isFrontSingleCameraPortraitModeSupported {
    return YES;
}
-(BOOL)isNeuralEngineSupported {
    return YES;
}
-(BOOL)isBackLowLightSupported {
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
		arg1 = 4;
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
%end
%hook CAMViewfinderViewController 
-(BOOL)_shouldUseZoomControlInsteadOfSlider {
    return YES;
}
%end
