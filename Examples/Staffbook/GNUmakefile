#
# Staffbook -- the FreeCoreData example application, for GNUstep.
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
PACKAGE_NAME = Staffbook
APP_NAME = Staffbook

Staffbook_RESOURCE_FILES = \
    Resources/MainMenu.xib \
    Resources/EmployeeWindow.xib \
    Resources/EmployeeEditor.xib

# Compiled to Staffbook.momd by FreeCoreData's momc and added to the
# resources; the fragment lives at this repository's root.
Staffbook_XCDATAMODELD_FILES = Staffbook.xcdatamodeld

Staffbook_OBJC_FILES = \
    SBAppDelegate.m \
    SBChartView.m \
    SBEmployeeEditorController.m \
    SBEmployeeWindowController.m \
    SBManagedObjects.m \
    main.m

Staffbook_HEADER_FILES = $(wildcard *.h)

Staffbook_GUI_LIBS += -lCoreData

-include GNUmakefile.preamble
include ../../coredata-model.make
include $(GNUSTEP_MAKEFILES)/application.make
-include GNUmakefile.postamble
