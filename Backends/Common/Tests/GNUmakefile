# Both SQL backends in one process: that they share one CDSQLStore, and,
# given both servers, that a store of each works side by side.
#
#   make -C Backends/Common/Tests run-tests
#   CD_TEST_POSTGRES_URL=postgresql://... CD_TEST_MYSQL_URL=mysql://... \
#       make -C Backends/Common/Tests run-tests
#
# The fixture the backends' own suites share (CDSQLStoreTestCase and
# CDSQLStoreTestBodies.inc) is in this directory too, compiled by those
# suites; this bundle is only the test of the two together.

BUNDLE_NAME = CDSQLBackendsTogetherTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0

include $(GNUSTEP_MAKEFILES)/common.make

CDSQLBackendsTogetherTests_OBJC_FILES = CDSQLBackendsTogetherTests.m
CDSQLBackendsTogetherTests_OBJCFLAGS = -fno-objc-arc

# -I.. is CDSQLStore.h, the backends' own directories their headers, and
# -I../../.. the repository root (for <CoreData/CoreData.h>).
CDSQLBackendsTogetherTests_INCLUDE_DIRS = -I.. -I../../PostgreSQL -I../../MySQL -I../../..

FRAMEWORK_BUILD_DIR = $(CURDIR)/../../../CoreData.framework/Versions/Current
COMMON_BUILD_DIR = $(CURDIR)/../$(GNUSTEP_OBJ_DIR_NAME)
POSTGRES_BUILD_DIR = $(CURDIR)/../../PostgreSQL/$(GNUSTEP_OBJ_DIR_NAME)
MYSQL_BUILD_DIR = $(CURDIR)/../../MySQL/$(GNUSTEP_OBJ_DIR_NAME)

ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR) -L$(COMMON_BUILD_DIR) -L$(POSTGRES_BUILD_DIR) -L$(MYSQL_BUILD_DIR) -L$(GNUSTEP_SYSTEM_LIBRARIES)

CDSQLBackendsTogetherTests_OBJC_LIBS += -lCDPostgreSQLStore -lCDMySQLStore -lCDSQLStore -lCoreData -lXCTest

XCTEST ?= xctest

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble

.PHONY: run-tests backends
backends:
	$(MAKE) -C ../../..
	$(MAKE) -C ../../PostgreSQL
	$(MAKE) -C ../../MySQL

run-tests: backends all $(BUNDLE_NAME).bundle
	@echo "Running XCTest bundle: $(BUNDLE_NAME)"
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	LD_LIBRARY_PATH="$(FRAMEWORK_BUILD_DIR):$(COMMON_BUILD_DIR):$(POSTGRES_BUILD_DIR):$(MYSQL_BUILD_DIR):$$LD_LIBRARY_PATH" \
	$(XCTEST) "$(BUNDLE_NAME).bundle"
