#import "../PSHeader/Misc.h"
#import <substrate.h>
#import <CoreFoundation/CoreFoundation.h>

extern "C" bool MGGetBoolAnswer(CFStringRef);
%hookf(bool, MGGetBoolAnswer, CFStringRef key) {
	if (CFStringEqual(key, CFSTR("nVh/gwNpy7Jv1NOk00CMrw")))
		return YES;
	return %orig;
}





    "cWWKdUn+rIclZ60ZGAVhBw": "CameraHDR2Capability",
    "FymLPtOEy6FdE7TmKeoTdg": "DeviceSupportsSingleCameraPortrait",
    "fYsrGTmVTbneEs3HKetEdQ": "FrontFacingCameraSingleCameraPortrait",
    "g/MkWm2Ac6+TLNBgtBGxsg": "HEVCEncodingCapability",
    "hewg+QX1h57eGJGphdCong": "DeviceSupportsPortraitLightEffectFilters",
   "ik8OQ5JoYhyK8AoTx29MuA": "DeviceSupportsOnDemandPhotoAnalysis",
    "IMUksyctl4kC/BFI2K/Qyw": "DeviceSupportsStageLightPortraitPreview",
    "jaJWtlotaa+Y41lCs7NVHg": "RearFacingLowLightCameraCapability",
    "jBGZJ71pRJrqD8VZ6Tk2VQ": "RearFacingCameraVideoCapture1080pMaxFPS",
    "L8CqbJeM+rf7l7NSOjnAHg": "DeviceSupportsPortraitIntensityAdjustments",
    "Lcu6Zck+C/+AMO8qULacDw": "DeviceSupportsToneMapping",
    "NszbG6qiAztVal4mpDQRkg": "CameraAppUIVersion",
    "oLjiDs+BWEdMVbjE0x6cnw": "DeviceSupportsStudioLightPortraitPreview",
    "po7g0ATDzGoVI1DO8ISmuw": "RearFacingCameraVideoCapture4kMaxFPS",
    "PpmzzBVLpZVubmP0tCIymg": "WirelessChargingCapability",
    "pQzfsK0Ado+nkNFgPRIA8Q": "DeviceSupportsLivePhotoAuto",
    "RLlZndRrTB3oIDuZEihtpQ": "RearFacingCameraAutoHDRCapability",
    "SjQQ07G8UacM7E69G7dPbg": "DeviceSupportsSpatialOverCapture",
    "sQwlfROu8fcD1Qwm8YJVeg": "DeviceSupportsReverseZoom",
    "WXi7NQbOKnEX4vPQFeZAdQ": "DeviceSupportsSiriBargeIn",
    "XIcF5FOyQlt/H79oFw9ciA": "PipelinedStillImageProcessingCapability",
    "yZf3GTRMGTuwSV/lD7Cagw": "DeviceSupportsTapToWake"
    "YlK+0xmxNWhNn/+r8SM8kA": "DeviceSupportsStereoAudioRecording",