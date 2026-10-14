include $(GNUSTEP_MAKEFILES)/common.make

# The framework as this repository builds it, not one installed, and the
# momc built beside it (the root GNUmakefile builds both first).
FRAMEWORK_BUILD_DIR = $(firstword $(wildcard $(CURDIR)/../../CoreData.framework/Versions/Current) $(CURDIR)/../../CoreData.framework)
ADDITIONAL_INCLUDE_DIRS += -I../..
ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR)
MOMC ?= LD_LIBRARY_PATH="$(FRAMEWORK_BUILD_DIR):$$LD_LIBRARY_PATH" PATH="$(FRAMEWORK_BUILD_DIR):$$PATH" $(CURDIR)/../../Tools/momc/obj/momc


APP_NAME = EmployeeDirectory

EmployeeDirectory_OBJC_FILES = \
	EmployeeDirectoryModel.m \
	EDAppDelegate.m \
	main.m

EmployeeDirectory_OBJCFLAGS = -fno-objc-arc
EmployeeDirectory_INCLUDE_DIRS = -I../..
EmployeeDirectory_GUI_LIBS += -lCoreData

# The compiled managed object model, kept in source control (its
# EmployeeDirectory.xcdatamodeld source is edited with Xcode on a Mac).
EmployeeDirectory_RESOURCE_FILES = EmployeeDirectory.momd

ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBRARIES)

include $(GNUSTEP_MAKEFILES)/application.make

.PHONY: run
run: all
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	openapp ./EmployeeDirectory.app
