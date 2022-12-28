#import <UIKit/UIKit.h>
%hook CAMViewfinderViewController 
-(BOOL)_shouldUseZoomControlInsteadOfSlider {
    return YES;
}
%end
%hook CAMZoomDial
-(double)minAvailableZoomFactor{
                return 1.05;
}
-(BOOL)hideLabels {
                return YES;
}
-(NSArray *)zoomFactors{
                return [1.05,2,10];
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
-(bool)isExposureSliderSupported {
                return YES;
}
-(bool)isDepthEffectApertureSupported {
		return YES;
}
-(bool)isPortraitEffectIntensitySupported {
		return YES;
}
-(bool)isImageAnalysisSupported {
                return YES;
}
-(bool)isImageAnalysisButtonAlwaysVisible {
                return YES;
}
-(bool)isSpatialOverCaptureSupported {                  //View Outside the Frame
    return YES;
}
-(bool)isBackSpatialOverCaptureSupported {                  
    return YES;
}
// -(double)_forcedInitialZoomDisplayFactor {                  
//    return 1.05;
//}
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
-(bool)isSpatialOverCaptureSupported {
		return YES;
}
-(float)spatialOverCapturePercentage {
		return 100;
}
%end

