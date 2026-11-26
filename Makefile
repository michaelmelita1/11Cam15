# Rootless by default. For rootful jailbreaks: make package ROOTFUL=1
ifneq ($(ROOTFUL),1)
THEOS_PACKAGE_SCHEME = rootless
endif

FINALPACKAGE ?= 1
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Camera Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = 11Cam
11Cam_FILES = Tweak.x
11Cam_CFLAGS = -fobjc-arc
11Cam_FRAMEWORKS = CoreMedia AVFoundation
ifneq ($(DIAG),)
11Cam_CFLAGS += $(foreach d,$(DIAG),-D$(d))
endif
ifneq ($(EXP),)
11Cam_CFLAGS += $(foreach e,$(EXP),-DEXP_$(e))
endif

include $(THEOS_MAKE_PATH)/tweak.mk
