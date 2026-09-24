# Tests for the PostgreSQL backend.
#
#   make -C Backends/PostgreSQL/Tests
#   CD_TEST_POSTGRES_URL=postgresql://localhost/coredata_test \
#       make -C Backends/PostgreSQL/Tests run-tests
#
# Without CD_TEST_POSTGRES_URL in the environment every test returns
# immediately, so `run-tests` is safe to run on a machine with no server.
#
# CD_TEST_REQUIRE_DATABASE makes that a failure instead, for CI, where a
# server that did not start must not pass for a suite that did.

BUNDLE_NAME = CDPostgreSQLStoreTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

CDPostgreSQLStoreTests_OBJC_FILES = CDPostgreSQLStoreTests.m

# -I../../.. is the repository root (for <CoreData/CoreData.h>), -I.. the
# backend's own header.
# The tests link libpq themselves: one of them drops the store's connection
# from a second connection of its own, to check that the store recovers.
PG_CONFIG ?= pg_config
PG_INCLUDEDIR := $(shell $(PG_CONFIG) --includedir 2>/dev/null)
PG_LIBDIR := $(shell $(PG_CONFIG) --libdir 2>/dev/null)

ifneq ($(PG_INCLUDEDIR),)
ADDITIONAL_INCLUDE_DIRS += -I$(PG_INCLUDEDIR)
endif
ifneq ($(PG_LIBDIR),)
ADDITIONAL_LIB_DIRS += -L$(PG_LIBDIR)
endif

CDPostgreSQLStoreTests_INCLUDE_DIRS = -I.. -I../../Common -I../../..

FRAMEWORK_BUILD_DIR = $(CURDIR)/../../../CoreData.framework/Versions/Current
BACKEND_BUILD_DIR = $(CURDIR)/../$(GNUSTEP_OBJ_DIR_NAME)

ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR) -L$(BACKEND_BUILD_DIR) -L$(GNUSTEP_SYSTEM_LIBRARIES)

CDPostgreSQLStoreTests_OBJC_LIBS += -lCDPostgreSQLStore -lCoreData -lXCTest -lpq

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
