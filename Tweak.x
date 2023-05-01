#import <UIKit/UIKit.h>

%hook CAMViewfinderViewController 
-(BOOL)_shouldUseZoomControlInsteadOfSlider { //New Camera App Code
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
-(bool)allowDynamicShutterZoom {
                return YES;
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
-(bool)sfCameraFontSupported {
                return YES;
}
-(bool)isLivePhotoAutoModeSupported {
		return YES;
}
-(bool)isExposureSliderSupported {
                return YES;
}
-(bool)arePortraitEffectsSupported {     //Portrait Lighting Code
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
-(bool)isPortraitEffectIntensitySupported {
		return YES;
}
-(bool)isLivePreviewSupportedForLightingType:(long long)arg1 devicePosition:(long long)arg2 {
		return YES;
		arg1 = 1;
		arg2 = 1;
}
-(bool)isDepthEffectApertureSupported {  //Portrait Depth Effect Code
		return YES;
}
-(bool)isImageAnalysisSupported {                       //Live Text Code
                return YES;
}
-(bool)isImageAnalysisButtonAlwaysVisible {
                return YES;
}
-(bool)isSpatialOverCaptureSupported {                  //View Outside the Frame Code
                return YES;
}
-(bool)isBackSpatialOverCaptureSupported {                  
                return YES;
}
-(bool)isBack4k60VideoSupported {  // iPhone 7 and 7 Plus Feature Unlock
                return YES;
}
-(bool)isBack1080p240Supported {                  
                return YES;
}
-(bool)isBack4k24VideoSupported {                  
                return YES;
}
%end
%hook CAMUserPreferences   //Hook Cam User Preferences to ensure the function enabled
-(bool)shouldUseVolumeUpBurst {
                return YES;
}		
-(bool)isPhotoOverCaptureEnabled {
                return YES;
}
-(bool)isOverCapturePreviewEnabled {
                return YES;
}
-(bool)isImageAnalysisEnabled {
                return YES;
}
%end

%hook AVCaptureDeviceFormat				//Depth Control and Intensity Control Code
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
