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
-(bool)isImageAnalysisSupported {                       //Live Text Code
                return YES;
}
-(bool)isImageAnalysisButtonAlwaysVisible {
                return YES;
}
// iPhone 7 and 7 Plus Feature Unlock

-(bool)isBack4k60VideoSupported {
                return YES;
}
-(bool)isBack1080p240Supported {                  
                return YES;
}
-(bool)isBack4k24VideoSupported {                  
                return YES;
}
-(bool)interactiveVideoFormatControlAlwaysEnabled {     // Force for Video Format Control Working on 4k60              
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
