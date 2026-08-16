BUNDLE_NAME = CoreDataTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

CoreDataTests_OBJC_FILES = CoreDataTests.m

CoreDataTests_INCLUDE_DIRS = -I.. -I../CoreData

ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBRARIES)
CoreDataTests_OBJC_LIBS += -lgnustep-corebase -lCoreData -lXCTest

XCTEST ?= xctest

.PHONY: check run-tests
run-tests: all $(BUNDLE_NAME).bundle
	@echo "Running XCTest bundle: $(BUNDLE_NAME)"
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	$(XCTEST) "$(BUNDLE_NAME).bundle"

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble
