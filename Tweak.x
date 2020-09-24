@interface CAMViewfinderViewController
- (NSInteger)_currentMode;
@end
@interface CAMZoomControl : UIView
- (id)_viewControllerForAncestor;
- (void)setHidden:(BOOL)arg1;
- (void)_handleButtonTappedForTripleCameraMode:(id)arg1;
@end
NSInteger cameraMode;
%hook CAMZoomControl							//11 Pro Zoom Dial
- (void)_configureForControlMode:(long long)arg1 zoomFactor:(double)arg2 zoomFactors:(id)arg3 displayZoomFactors:(id)arg4 zoomButtonContentType:(long long)arg5 animated:(BOOL)arg6 {
	cameraMode = [[self _viewControllerForAncestor] _currentMode];
[self setHidden:0];
	switch(cameraMode) {
   	case 0 : // Photo mode						//Zoom Factors for Dial
		arg3 = @[@1, @2, @3, @10];				
		arg4 = @[@1, @2, @3, @10];
   	  	break;
   	case 1 : // Video mode	
		arg3 = @[@1, @2, @3, @6];
		arg4 = @[@1, @2, @3, @6];	
   	  	break;
	}
	%orig;	
}
-(bool)_isButtonPlatterSupportedForConfiguration {
	if (cameraMode == 0 | cameraMode == 1) {
		return true; 
	} else {
		return false;
	}
}
-(void)_handleButtonTapped:(id)arg1 {
	if (cameraMode == 0 | cameraMode == 1) {
		[self _handleButtonTappedForTripleCameraMode:arg1];
	} else {
		%orig;
	}
}
%end
%hook CAMCaptureCapabilities
-(bool)isTripleCameraSupported {
	return YES;
}
-(long long) zoomDialStyle {
		return 1;
}
-(bool)isCTMSupported {
    return YES;
}
-(bool)arePortraitEffectsSupported {
		return YES;
}
-(double)defaultZoomFactorForMode:(long long)arg1 device:(long long)arg2 videoConfiguration:(long long)arg3 captureOrientation:(long long)arg4 {
	return 1;
}
-(long long)supportedPortraitLightingVersion {	
                return 2;
}
-(bool)isLivePreviewSupportedForLightingType:(long long)arg1 devicePosition:(long long)arg2 {
		return YES;
		arg1 = 1;
		arg2 = 1;
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
