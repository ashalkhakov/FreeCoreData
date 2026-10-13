#
# Staffbook -- the FreeCoreData example application, for GNUstep.
#
# Built by the repository's GNUmakefile, after the framework and momc,
# against both as they are built there; MOMC=... for another momc.
#
ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error GNUSTEP_MAKEFILES is not set. Source GNUstep.sh or install gnustep-make.)
endif

include $(GNUSTEP_MAKEFILES)/common.make

# The framework as this repository builds it, not one installed, and the
# momc built beside it (the root GNUmakefile builds both first).
FRAMEWORK_BUILD_DIR = $(CURDIR)/../../CoreData.framework/Versions/Current
ADDITIONAL_INCLUDE_DIRS += -I../..
ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR)
MOMC ?= LD_LIBRARY_PATH="$(FRAMEWORK_BUILD_DIR):$$LD_LIBRARY_PATH" $(CURDIR)/../../Tools/momc/obj/momc


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
