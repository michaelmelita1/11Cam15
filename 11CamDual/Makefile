FINALPACKAGE=1
ARCHS = arm64
TARGET = iphone:14.5
INSTALL_TARGET_PROCESSES = Camera

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = 11CamDual
11CamDual_FILES = Tweak.x
11CamDual_CFLAGS = -fobjc-arc
11CamDual_INSTALL_PATH = /Library/Application Support/11Cam/Dual

include $(THEOS_MAKE_PATH)/tweak.mk