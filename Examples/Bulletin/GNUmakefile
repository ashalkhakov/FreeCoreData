#
# Bulletin -- the FreeCoreData persistent-history example, for GNUstep.
#
# Needs the framework this repository builds (installed, or pointed at
# with ADDITIONAL_*_DIRS), gnustep-gui, and momc on PATH (or MOMC=...).
#
ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error GNUSTEP_MAKEFILES is not set. Source GNUstep.sh or install gnustep-make.)
endif

include $(GNUSTEP_MAKEFILES)/common.make

VERSION = 0.1
PACKAGE_NAME = Bulletin
APP_NAME = Bulletin

Bulletin_RESOURCE_FILES = \
    Resources/MainMenu.xib \
    Resources/BoardWindow.xib \
    Resources/HistoryWindow.xib

# Compiled to Bulletin.momd by FreeCoreData's momc and added to the
# resources; the fragment lives at this repository's root.
Bulletin_XCDATAMODELD_FILES = Bulletin.xcdatamodeld

Bulletin_OBJC_FILES = \
    BLAppDelegate.m \
    BLBoardWindowController.m \
    BLHistoryWindowController.m \
    BLManagedObjects.m \
    main.m

Bulletin_HEADER_FILES = $(wildcard *.h)

Bulletin_GUI_LIBS += -lCoreData

-include GNUmakefile.preamble
include ../../coredata-model.make
include $(GNUSTEP_MAKEFILES)/application.make
-include GNUmakefile.postamble
