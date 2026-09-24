# Tests for the PostgreSQL backend.
#
#   make -C Backends/PostgreSQL/Tests
#   CD_TEST_MYSQL_URL=mysql://root:test@localhost/coredata_test \
#       make -C Backends/PostgreSQL/Tests run-tests
#
# Without CD_TEST_MYSQL_URL in the environment every test returns
# immediately, so `run-tests` is safe to run on a machine with no server.
#
# CD_TEST_REQUIRE_DATABASE makes that a failure instead, for CI, where a
# server that did not start must not pass for a suite that did.

BUNDLE_NAME = CDMySQLStoreTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

CDMySQLStoreTests_OBJC_FILES = CDMySQLStoreTests.m

# -I../../.. is the repository root (for <CoreData/CoreData.h>), -I.. the
# backend's own header.
# The tests link the client library themselves: one of them drops the store's connection
# from a second connection of its own, to check that the store recovers.
MYSQL_CONFIG ?= $(shell which mariadb_config 2>/dev/null || which mysql_config 2>/dev/null)

ifneq ($(MYSQL_CONFIG),)
MYSQL_CFLAGS := $(shell $(MYSQL_CONFIG) --include 2>/dev/null)
MYSQL_LIBS := $(shell $(MYSQL_CONFIG) --libs 2>/dev/null)
else
MYSQL_CFLAGS := -I/usr/include/mysql -I/usr/include/mariadb
MYSQL_LIBS := -lmariadb
endif

ADDITIONAL_INCLUDE_DIRS += $(MYSQL_CFLAGS)

CDMySQLStoreTests_INCLUDE_DIRS = -I.. -I../../Common -I../../..

FRAMEWORK_BUILD_DIR = $(CURDIR)/../../../CoreData.framework/Versions/Current
BACKEND_BUILD_DIR = $(CURDIR)/../$(GNUSTEP_OBJ_DIR_NAME)

ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR) -L$(BACKEND_BUILD_DIR) -L$(GNUSTEP_SYSTEM_LIBRARIES)

CDMySQLStoreTests_OBJC_LIBS += -lCDMySQLStore -lCoreData -lXCTest $(MYSQL_LIBS)

XCTEST ?= xctest

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble

# Named run-tests rather than check, which gnustep-make already defines as a
# double-colon rule (as Tests/GNUmakefile does for the same reason).
.PHONY: run-tests backend
backend:
	$(MAKE) -C ../../..
	$(MAKE) -C ..

run-tests: backend all $(BUNDLE_NAME).bundle
	@echo "Running XCTest bundle: $(BUNDLE_NAME)"
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	LD_LIBRARY_PATH="$(FRAMEWORK_BUILD_DIR):$(BACKEND_BUILD_DIR):$$LD_LIBRARY_PATH" \
	$(XCTEST) "$(BUNDLE_NAME).bundle"
