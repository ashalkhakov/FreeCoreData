#
# CDLauncher -- the app chooser inside the AppImage (GNUstep only).
# A Mac ships ModelBuilder.app and the samples separately and has
# nothing to choose between, so there is no Xcode target for this.
#
ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error GNUSTEP_MAKEFILES is not set. Source GNUstep.sh or install gnustep-make.)
endif

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = CDLauncher

CDLauncher_OBJC_FILES = \
	main.m \
	CDLauncherAppDelegate.m

CDLauncher_OBJCFLAGS += -fobjc-arc -Wall -Wextra
CDLauncher_MAIN_MODEL_FILE =

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/application.make
-include GNUmakefile.postamble
