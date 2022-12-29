include $(THEOS)/makefiles/common.mk

AGGREGATE_NAME = 11Cam15
SUBPROJECTS += 11CamSingle 11CamDual

after-install::
	install.exec "killall -9 SpringBoard"
	
include $(THEOS_MAKE_PATH)/aggregate.mk