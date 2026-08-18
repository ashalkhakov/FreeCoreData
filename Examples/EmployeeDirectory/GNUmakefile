include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = EmployeeDirectory

EmployeeDirectory_OBJC_FILES = \
	EmployeeDirectoryModel.m \
	EDAppDelegate.m \
	main.m

EmployeeDirectory_OBJCFLAGS = -fno-objc-arc
EmployeeDirectory_INCLUDE_DIRS = -I../..
EmployeeDirectory_GUI_LIBS += -lCoreData

ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBRARIES)

include $(GNUSTEP_MAKEFILES)/application.make

.PHONY: run
run: all
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	openapp ./EmployeeDirectory.app
