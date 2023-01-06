include $(THEOS)/makefiles/common.mk

AGGREGATE_NAME = 11Cam15
SUBPROJECTS += 11CamPrefs 11CamDual

after-install::
	install.exec "ldrestart"

include $(THEOS_MAKE_PATH)/aggregate.mk