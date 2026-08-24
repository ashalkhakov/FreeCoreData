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
	NSTransformableAttributeTests.m \
	NSDerivedAttributeTests.m \
	NSCountAndExistingObjectTests.m \
	NSPendingChangesFetchTests.m \
	MomcCompiledModelTests.m \
	NSUUIDAndOrderedRelationshipTests.m \
	NSManagedObjectContextUndoTests.m \
	VersionHashTests.m \
	MappingModelTests.m \
	StoreVersioningTests.m

CoreDataTests_INCLUDE_DIRS = -I.. -I../CoreData

# Link and run against the freshly built, uninstalled framework in the
# source tree, not whatever CoreData is installed in the GNUstep domains.
FRAMEWORK_BUILD_DIR = $(CURDIR)/../CoreData.framework/Versions/Current

ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR) -L$(GNUSTEP_SYSTEM_LIBRARIES)
CoreDataTests_OBJC_LIBS += -lCoreData -lXCTest

XCTEST ?= xctest

# Dogfood the model compiler: MomcFixture.xcdatamodeld is compiled with
# the freshly built momc through the same makefile fragment other
# projects use, and lands in the bundle's resources.  (On macOS, Xcode
# compiles the identical source with Apple's momc.)
#
# momc runs under a PINNED library path: the build-tree framework
# first, then the GNUstep library domains - deliberately ahead of
# whatever the surrounding environment prepended (a CI shell that puts
# a prefix's bare lib/ directory first would otherwise hand momc any
# stale copies living there).
CoreDataTests_XCDATAMODELD_FILES = MomcFixture.xcdatamodeld
MOMC = LD_LIBRARY_PATH="$(FRAMEWORK_BUILD_DIR):$(GNUSTEP_LOCAL_LIBRARIES):$(GNUSTEP_SYSTEM_LIBRARIES):$$LD_LIBRARY_PATH" \
       ../Tools/momc/obj/momc

include ../coredata-model.make

MomcFixture.momd: ../Tools/momc/obj/momc

.PHONY: momc-tool
momc-tool:
	$(MAKE) -C ../Tools/momc

../Tools/momc/obj/momc: momc-tool

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble

# Custom rules live below the bundle.make include so that plain 'make'
# still defaults to building the bundle.
.PHONY: check run-tests framework
framework:
	$(MAKE) -C ..
	$(MAKE) -C ../Tools/momc

run-tests: framework all $(BUNDLE_NAME).bundle
	@echo "Running XCTest bundle: $(BUNDLE_NAME)"
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	LD_LIBRARY_PATH="$(FRAMEWORK_BUILD_DIR):$$LD_LIBRARY_PATH" \
	$(XCTEST) "$(BUNDLE_NAME).bundle"
