BUNDLE_NAME = CoreDataTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

CoreDataTests_OBJC_FILES = \
	MemoryIncrementalStore.m \
	VersioningTestModels.m \
	NSManagedObjectModelTests.m \
	NSFetchRequestTests.m \
	NSPersistentStoreCoordinatorTests.m \
	NSManagedObjectContextTests.m \
	NSFetchedResultsControllerTests.m \
	NSManagedObjectValidationTests.m \
	NSManagedObjectLifecycleTests.m \
	NSMergePolicyTests.m \
	NSPersistentStoreCoordinatorTypeMismatchTests.m \
	NSPersistentStoreRequestTests.m \
	NSIncrementalStoreNodeTests.m \
	NSIncrementalStoreTests.m \
	NSXMLPersistentStoreTests.m \
	NSSQLitePersistentStoreTests.m \
	VersionHashTests.m \
	MappingModelTests.m \
	StoreVersioningTests.m \
	NSTransformableAttributeTests.m \
	NSDerivedAttributeTests.m \
	NSCountAndExistingObjectTests.m \
	NSPendingChangesFetchTests.m

CoreDataTests_INCLUDE_DIRS = -I.. -I../CoreData

# Link and run against the freshly built, uninstalled framework in the
# source tree, not whatever CoreData is installed in the GNUstep domains.
FRAMEWORK_BUILD_DIR = $(CURDIR)/../CoreData.framework/Versions/Current

ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR) -L$(GNUSTEP_SYSTEM_LIBRARIES)
CoreDataTests_OBJC_LIBS += -lCoreData -lXCTest

XCTEST ?= xctest

.PHONY: check run-tests
run-tests: all $(BUNDLE_NAME).bundle
	@echo "Running XCTest bundle: $(BUNDLE_NAME)"
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	LD_LIBRARY_PATH="$(FRAMEWORK_BUILD_DIR):$$LD_LIBRARY_PATH" \
	$(XCTEST) "$(BUNDLE_NAME).bundle"

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble
