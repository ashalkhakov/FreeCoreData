include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = EmployeeDirectory

EmployeeDirectory_OBJC_FILES = \
	EmployeeDirectoryModel.m \
	main.m

EmployeeDirectory_OBJCFLAGS = -fno-objc-arc
EmployeeDirectory_INCLUDE_DIRS = -I../..
EmployeeDirectory_TOOL_LIBS += -lCoreData

ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBRARIES)

include $(GNUSTEP_MAKEFILES)/tool.make

.PHONY: run
run: all
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	$(GNUSTEP_OBJ_DIR)/EmployeeDirectory
