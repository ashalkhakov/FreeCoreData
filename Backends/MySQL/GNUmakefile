# MySQL/MariaDB backend (addon).
#
# Not built by the top-level makefile: build it here, against the framework
# already built in the tree.
#
#   make -C Backends/PostgreSQL
#
# The client library is found through mariadb_config or mysql_config when
# one is on PATH (MYSQL_CONFIG overrides the choice); failing that, the
# compiler's default search paths are used.  MariaDB Connector/C talks to
# MySQL servers too, so either package serves.

include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = libCDMySQLStore

libCDMySQLStore_OBJC_FILES = CDMySQLStore.m ../Common/CDSQLStore.m

libCDMySQLStore_HEADER_FILES = CDMySQLStore.h ../Common/CDSQLStore.h
libCDMySQLStore_HEADER_FILES_DIR = .
libCDMySQLStore_HEADER_FILES_INSTALL_DIR = CDMySQLStore

# The framework is built without ARC and this store follows the same
# retain/release conventions (-newValuesForObjectWithID: and
# -newValueForRelationship: hand back retained objects).
libCDMySQLStore_OBJCFLAGS = -fno-objc-arc

MYSQL_CONFIG ?= $(shell which mariadb_config 2>/dev/null || which mysql_config 2>/dev/null)

ifneq ($(MYSQL_CONFIG),)
MYSQL_CFLAGS := $(shell $(MYSQL_CONFIG) --include 2>/dev/null)
MYSQL_LIBS := $(shell $(MYSQL_CONFIG) --libs 2>/dev/null)
else
MYSQL_CFLAGS := -I/usr/include/mysql -I/usr/include/mariadb
MYSQL_LIBS := -lmariadb
endif

ADDITIONAL_INCLUDE_DIRS += $(MYSQL_CFLAGS)

# -I../.. is the repository root, so that <CoreData/CoreData.h> resolves to
# the headers of the framework built in this tree.
FRAMEWORK_BUILD_DIR = $(CURDIR)/../../CoreData.framework/Versions/Current

ADDITIONAL_INCLUDE_DIRS += -I../.. -I../Common
ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR)

libCDMySQLStore_LIBRARIES_DEPEND_UPON += -lCoreData $(MYSQL_LIBS)

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/library.make

-include GNUmakefile.postamble

.PHONY: framework
framework:
	$(MAKE) -C ../..
