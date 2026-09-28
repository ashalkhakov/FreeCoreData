# The half of a SQL backend that does not depend on the server (addon).
#
# Built once, as a library of its own that every backend links, so that a
# process can load more than one backend: were CDSQLStore and CDSQLQuery
# compiled into each backend, a process loading two would have two classes
# of each name, and the runtime would keep one, whose methods are not the
# other backend's.
#
#   make -C Backends/Common
#
# The backends build it themselves (make -C Backends/PostgreSQL does).

include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = libCDSQLStore

libCDSQLStore_OBJC_FILES = CDSQLStore.m CDSQLQuery.m

libCDSQLStore_HEADER_FILES = CDSQLStore.h CDSQLQuery.h
libCDSQLStore_HEADER_FILES_DIR = .
libCDSQLStore_HEADER_FILES_INSTALL_DIR = CDSQLStore

# The framework is built without ARC, and the stores follow the same
# retain/release conventions.
libCDSQLStore_OBJCFLAGS = -fno-objc-arc

# -I../.. is the repository root, so that <CoreData/CoreData.h> resolves to
# the headers of the framework built in this tree.
FRAMEWORK_BUILD_DIR = $(CURDIR)/../../CoreData.framework/Versions/Current

ADDITIONAL_INCLUDE_DIRS += -I../..
ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR)

libCDSQLStore_LIBRARIES_DEPEND_UPON += -lCoreData

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/library.make

-include GNUmakefile.postamble
