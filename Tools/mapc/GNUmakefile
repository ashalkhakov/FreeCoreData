TOOL_NAME = mapc

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

mapc_OBJC_FILES = mapc.m CDMappingCompiler.m ../momc/CDModelCompiler.m

mapc_INCLUDE_DIRS = -I../.. -I../../CoreData -I../momc

# Link against the freshly built, uninstalled framework in the source
# tree when present, falling back to the installed one.
FRAMEWORK_BUILD_DIR = $(CURDIR)/../../CoreData.framework/Versions/Current

ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR) -L$(GNUSTEP_SYSTEM_LIBRARIES)
mapc_TOOL_LIBS += -lCoreData

include $(GNUSTEP_MAKEFILES)/tool.make
