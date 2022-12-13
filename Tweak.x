#import <UIKit/UIKit.h>
%hook CAMViewfinderViewController 
-(bool)_shouldUseZoomControlInsteadOfSlider {
    return YES;
}
%end
%hook CAMCaptureCapabilities
-(bool)isZoomPlatterSupported {
                return YES;
}
-(long long)zoomDialStyle {
		return 1;
}
-(bool)isCTMSupported {
                return YES;
}
-(bool)isCTMSupportSupressed {
                 return NO;
}
-(bool)deviceSupportsCTM {
                 return YES;
}
-(bool) allowDynamicShutterZoom {
                return YES;
}
-(bool) sfCameraFontSupported {
                return YES;
}
-(bool)arePortraitEffectsSupported {
		return YES;
}
-(long long)supportedPortraitLightingVersion {	
                return 2;
}
-(bool)backStageLightPortaitEffectsSupported {
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
-(bool)isExposureSliderSupported {
                return YES;
}
-(bool)isImageAnalysisSupported {                      //LiveText
                return YES;
}
-(bool)isImageAnalysisButtonAlwaysVisible {
                return YES;
}
-(bool)isSpatialOverCaptureSupported {                  //View Outside the Frame Test
    return YES;
}
-(bool)isBackSpatialOverCaptureSupported {
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
-(bool)isMultiCamSupported {
		return YES;
}
-(bool)isContentAwareDistortionCorrectionSupported {
		return YES;
}
-(bool)isSpatialOverCaptureSupported {
		return YES;
}
%end
