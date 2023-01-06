FINALPACKAGE=1
ARCHS = arm64
TARGET = iphone:14.5

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = 11CamPrefs
$(TWEAK_NAME)_FILES = Tweak.xm
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FRAMEWORKS = CoreMedia
$(TWEAK_NAME)_LIBRARIES = MobileGestalt

include $(THEOS_MAKE_PATH)/tweak.mk