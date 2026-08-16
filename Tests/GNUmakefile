include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = CoreDataTests

CoreDataTests_OBJC_FILES = CoreDataTests.m

# Tests use ARC; the framework itself is still MRC.
CoreDataTests_OBJCFLAGS = -fobjc-arc

CoreDataTests_INCLUDE_DIRS = -I.. -I../CoreData

CoreDataTests_FRAMEWORK_DIRS = ..
CoreDataTests_FRAMEWORKS   = CoreData
CoreDataTests_LIBRARIES    = objc gnustep-base XCTest

XCTEST ?= xctest

.PHONY: check run-tests
run-tests: all $(BUNDLE_NAME).bundle
	@echo "Running XCTest bundle: $(BUNDLE_NAME)"
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	$(XCTEST) "$(BUNDLE_NAME).bundle"

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble
