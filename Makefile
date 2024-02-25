FINALPACKAGE=1
THEOS_PACKAGE_SCHEME=rootless
ARCHS = arm64
TARGET := iphone:clang:latest
INSTALL_TARGET_PROCESSES = Camera

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = 11Cam15
11Cam15_FILES = Tweak.x
11Cam15_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "sbreload"
include $(THEOS_MAKE_PATH)/aggregate.mk
