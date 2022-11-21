#import <UIKit/UIKit.h>

%hook CAMCaptureCapabilities

-(BOOL)featureDevelopmentForceSingleCamera {
    return YES;
}
-(BOOL)isBackWideDualSupported {
    return YES;
}
-(BOOL)isZoomPlatterSupported {
    return YES;
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
-(BOOL)enableSemanticDevelopmentFilterDebugging {
    return YES;
}
-(BOOL)semanticDevelopmentSupported {
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
