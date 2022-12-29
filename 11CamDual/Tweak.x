#import <UIKit/UIKit.h>

@interface CAMViewfinderViewController
- (NSInteger)_currentMode;
@end
@interface CAMZoomControl : UIView
- (id)_viewControllerForAncestor;
- (void)setHidden:(BOOL)arg1;
@end
NSInteger cameraMode;

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
-(bool)isBack4k60VideoSupported {
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
-(double)_forcedInitialZoomDisplayFactor {              //View Outside the Frame Fix - Janky
	if (cameraMode == 0) {
		return 1.05; 
	} else {
		return %orig;
	}
}
%end
%hook CAMZoomControl							
- (void)_configureForControlMode:(long long)arg1 zoomFactor:(double)arg2 zoomFactors:(id)arg3 displayZoomFactors:(id)arg4 zoomButtonContentType:(long long)arg5 animated:(BOOL)arg6 {
	cameraMode = [[self _viewControllerForAncestor] _currentMode];
[self setHidden:0];
	switch(cameraMode) {
   	case 0 : // Photo mode						
		arg3 = @[@1.05, @2, @10];				
		arg4 = @[@1, @2, @10];
   	  	break;
	}
	%orig;	
}
-(double)minimumZoomFactor {	
	if (cameraMode == 0) {
		return 1.05; 
	} else {
		return %orig;
	}
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
