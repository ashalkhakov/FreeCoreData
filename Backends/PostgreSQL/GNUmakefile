# PostgreSQL backend (addon).
#
# Not built by the top-level makefile: build it here, against the framework
# already built in the tree.
#
#   make -C Backends/PostgreSQL
#
# libpq is found through pg_config when it is on PATH (PG_CONFIG overrides
# it); failing that, the compiler's default search paths are used, which is
# what happens with Debian/Ubuntu's libpq-dev.

include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = libCDPostgreSQLStore

libCDPostgreSQLStore_OBJC_FILES = CDPostgreSQLStore.m

libCDPostgreSQLStore_HEADER_FILES = CDPostgreSQLStore.h
libCDPostgreSQLStore_HEADER_FILES_DIR = .
libCDPostgreSQLStore_HEADER_FILES_INSTALL_DIR = CDPostgreSQLStore

# The framework is built without ARC and this store follows the same
# retain/release conventions (-newValuesForObjectWithID: and
# -newValueForRelationship: hand back retained objects).
libCDPostgreSQLStore_OBJCFLAGS = -fno-objc-arc

PG_CONFIG ?= pg_config
PG_INCLUDEDIR := $(shell $(PG_CONFIG) --includedir 2>/dev/null)
PG_LIBDIR := $(shell $(PG_CONFIG) --libdir 2>/dev/null)

ifneq ($(PG_INCLUDEDIR),)
ADDITIONAL_INCLUDE_DIRS += -I$(PG_INCLUDEDIR)
endif
ifneq ($(PG_LIBDIR),)
ADDITIONAL_LIB_DIRS += -L$(PG_LIBDIR)
endif

# -I../.. is the repository root, so that <CoreData/CoreData.h> resolves to
# the headers of the framework built in this tree.
FRAMEWORK_BUILD_DIR = $(CURDIR)/../../CoreData.framework/Versions/Current
# CDSQLStore, the part every SQL backend shares: a library of its own
# (Common/GNUmakefile says why), built first.
COMMON_BUILD_DIR = $(CURDIR)/../Common/$(GNUSTEP_OBJ_DIR_NAME)

ADDITIONAL_INCLUDE_DIRS += -I../.. -I../Common
ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR) -L$(COMMON_BUILD_DIR)

libCDPostgreSQLStore_LIBRARIES_DEPEND_UPON += -lCDSQLStore -lCoreData -lpq

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/library.make

-include GNUmakefile.postamble

# CDSQLStore first: this library links it.
before-all::
	$(MAKE) -C ../Common

# Installing a backend installs the library it links.
after-install::
	$(MAKE) -C ../Common install

.PHONY: framework
framework:
	$(MAKE) -C ../..
