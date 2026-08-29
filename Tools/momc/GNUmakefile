TOOL_NAME = momc

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

momc_OBJC_FILES = momc.m CDModelCompiler.m CDModelSerializer.m CDCodeGenerator.m

momc_INCLUDE_DIRS = -I../.. -I../../CoreData

# Link against the freshly built, uninstalled framework in the source
# tree when present, falling back to the installed one.
FRAMEWORK_BUILD_DIR = $(CURDIR)/../../CoreData.framework/Versions/Current

ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR) -L$(GNUSTEP_SYSTEM_LIBRARIES)
momc_TOOL_LIBS += -lCoreData

include $(GNUSTEP_MAKEFILES)/tool.make

# Install the makefile fragment other projects include to compile
# .xcdatamodeld sources as part of their own build.
after-install::
	$(INSTALL_DATA) ../../coredata-model.make \
	    $(GNUSTEP_MAKEFILES)/coredata-model.make

after-uninstall::
	rm -f $(GNUSTEP_MAKEFILES)/coredata-model.make
