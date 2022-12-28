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
-(bool)isBack4k60VideoSupported {
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
%end
