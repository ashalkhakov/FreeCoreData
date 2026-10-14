TOOL_NAME = momc

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

momc_OBJC_FILES = momc.m CDModelCompiler.m CDModelSerializer.m CDCodeGenerator.m

momc_INCLUDE_DIRS = -I../.. -I../../CoreData

# Link against the freshly built, uninstalled framework in the source
# tree when present, falling back to the installed one. The framework is
# flat (no Versions/) where gnustep-make has no symlinks, as on Windows, and
# its DLL is found on PATH there, as the library is on LD_LIBRARY_PATH.
FRAMEWORK_BUILD_DIR = $(firstword $(wildcard $(CURDIR)/../../CoreData.framework/Versions/Current) $(CURDIR)/../../CoreData.framework)

ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR) -L$(GNUSTEP_SYSTEM_LIBRARIES)
momc_TOOL_LIBS += -lCoreData

include $(GNUSTEP_MAKEFILES)/tool.make

# Install the makefile fragment other projects include to compile
# .xcdatamodeld sources as part of their own build. Beside gnustep-make's
# own makefiles, which are not an installation directory, so DESTDIR is
# added here (a staged install, as a release archive is made from).
after-install::
	$(MKDIRS) $(DESTDIR)$(GNUSTEP_MAKEFILES)
	$(INSTALL_DATA) ../../coredata-model.make \
	    $(DESTDIR)$(GNUSTEP_MAKEFILES)/coredata-model.make

after-uninstall::
	rm -f $(DESTDIR)$(GNUSTEP_MAKEFILES)/coredata-model.make
