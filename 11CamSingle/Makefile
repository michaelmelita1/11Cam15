FINALPACKAGE=1
ARCHS = arm64
TARGET = iphone:14.5
INSTALL_TARGET_PROCESSES = Camera

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = 11Cam15Single
11Cam15Single_FILES = Tweak.x
11Cam15Single_CFLAGS = -fobjc-arc
11CamSingle_INSTALL_PATH = /Library/Application Support/11Cam/Single

include $(THEOS_MAKE_PATH)/tweak.mk
