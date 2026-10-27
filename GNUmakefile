include $(GNUSTEP_MAKEFILES)/common.make

FRAMEWORK_NAME = CoreData

CoreData_OBJC_FILES = \
	CoreData/CoreDataErrors.m \
	CoreData/CDObjectConstants.m \
	CoreData/CDBatchFaultingArray.m \
	CoreData/CDRowCache.m \
	CoreData/CDExternalDataStore.m \
	CoreData/NSManagedObjectModel.m \
	CoreData/NSEntityDescription.m \
	CoreData/NSPropertyDescription.m \
	CoreData/NSAttributeDescription.m \
	CoreData/NSDerivedAttributeDescription.m \
	CoreData/NSExpressionDescription.m \
	CoreData/NSFetchIndexDescription.m \
	CoreData/NSFetchIndexElementDescription.m \
	CoreData/NSRelationshipDescription.m \
	CoreData/NSFetchedPropertyDescription.m \
	CoreData/NSPersistentStoreRequest.m \
	CoreData/NSSaveChangesRequest.m \
	CoreData/NSAsynchronousFetchRequest.m \
	CoreData/NSPersistentStoreResult.m \
	CoreData/NSBatchInsertRequest.m \
	CoreData/NSBatchUpdateRequest.m \
	CoreData/NSBatchDeleteRequest.m \
	CoreData/NSPersistentHistoryToken.m \
	CoreData/NSPersistentHistoryChange.m \
	CoreData/NSPersistentHistoryTransaction.m \
	CoreData/NSPersistentHistoryChangeRequest.m \
	CoreData/NSFetchRequest.m \
	CoreData/NSManagedObject.m \
	CoreData/NSManagedObjectID.m \
	CoreData/NSManagedObjectContext.m \
	CoreData/NSManagedObjectSet.m \
	CoreData/NSManagedObjectMutableSet.m \
	CoreData/NSManagedObjectSetEnumerator.m \
	CoreData/NSPersistentStoreCoordinator.m \
	CoreData/NSPersistentStoreDescription.m \
	CoreData/NSPersistentContainer.m \
	CoreData/NSPersistentStore.m \
	CoreData/NSAtomicStore.m \
	CoreData/NSIncrementalStore.m \
	CoreData/NSIncrementalStoreNode.m \
	CoreData/NSAtomicStoreCacheNode.m \
	CoreData/NSXMLPersistentStore.m \
	CoreData/NSSQLitePersistentStore.m \
	CoreData/NSInMemoryPersistentStore.m \
	CoreData/NSPropertyMapping.m \
	CoreData/NSEntityMapping.m \
	CoreData/NSFetchRequestExpression.m \
	CoreData/NSMappingModel.m \
	CoreData/NSEntityMigrationPolicy.m \
	CoreData/NSMigrationManager.m \
	CoreData/NSMergePolicy.m \
	CoreData/NSFetchedResultsController.m

CoreData_HEADER_FILES_DIR = CoreData
CoreData_HEADER_FILES_INSTALL_DIR = CoreData

CoreData_HEADER_FILES = \
	CoreData.h \
	CoreDataErrors.h \
	CoreDataExports.h \
	NSAttributeDescription.h \
	NSDerivedAttributeDescription.h \
	NSExpressionDescription.h \
	NSFetchIndexDescription.h \
	CDExternalDataStore.h \
	NSFetchIndexElementDescription.h \
	NSAtomicStore.h \
	NSAtomicStoreCacheNode.h \
	NSEntityDescription.h \
	NSPersistentStoreRequest.h \
	NSSaveChangesRequest.h \
	NSAsynchronousFetchRequest.h \
	NSPersistentStoreResult.h \
	NSBatchInsertRequest.h \
	NSBatchUpdateRequest.h \
	NSBatchDeleteRequest.h \
	NSPersistentHistoryToken.h \
	NSPersistentHistoryChange.h \
	NSPersistentHistoryTransaction.h \
	NSPersistentHistoryChangeRequest.h \
	NSFetchRequest.h \
	NSFetchedPropertyDescription.h \
	NSIncrementalStore.h \
	NSIncrementalStoreNode.h \
	NSInMemoryPersistentStore.h \
	NSManagedObject.h \
	NSManagedObjectContext.h \
	NSManagedObjectID.h \
	NSManagedObjectModel.h \
	NSPersistentStore.h \
	NSPersistentStoreCoordinator.h \
	NSPersistentStoreDescription.h \
	NSPersistentContainer.h \
	NSPropertyDescription.h \
	NSRelationshipDescription.h \
	NSSQLitePersistentStore.h \
	NSXMLPersistentStore.h \
	NSPropertyMapping.h \
	NSEntityMapping.h \
	NSFetchRequestExpression.h \
	NSMappingModel.h \
	NSEntityMigrationPolicy.h \
	NSMigrationManager.h \
	NSMergePolicy.h \
	NSFetchedResultsController.h

CoreData_OBJCFLAGS = -fno-objc-arc

CoreData_LIBRARIES_DEPEND_UPON += -lsqlite3 -ldispatch

ADDITIONAL_INCLUDE_DIRS += -I/usr/local/include
ADDITIONAL_LIB_DIRS += -L/usr/local/lib

CoreData_INCLUDE_DIRS = -I.
# The framework exports its constants (CoreDataExports.h: dllexport while
# building it, dllimport for what links it, on Windows; nothing elsewhere).
CoreData_CPPFLAGS += -DBUILDING_COREDATA

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/framework.make

-include GNUmakefile.postamble

# The rest of the repository, after the framework they all build on, each
# against it as built here: momc (and the coredata-model.make fragment
# applications include), the SQL stores (where their client libraries are:
# libpq's pg_config, MariaDB's mariadb_config), Model Builder, the launcher
# and the sample applications. `make`, `make install` (DESTDIR=...) and `make
# clean` go through them all.
CD_PARTS = Tools/momc Backends/Common
ifneq ($(shell command -v pg_config 2>/dev/null),)
CD_PARTS += Backends/PostgreSQL
endif
ifneq ($(shell command -v mariadb_config 2>/dev/null)$(shell command -v mysql_config 2>/dev/null),)
CD_PARTS += Backends/MySQL
endif
CD_PARTS += ModelBuilder CDLauncher Examples/EmployeeDirectory Examples/Staffbook Examples/Bulletin

after-all::
	@for part in $(CD_PARTS); do $(MAKE) -C $$part || exit 1; done

after-install::
	@for part in $(CD_PARTS); do $(MAKE) -C $$part install || exit 1; done

after-clean::
	@for part in $(CD_PARTS) Tests Tests/ModelBuilder; do $(MAKE) -C $$part clean || exit 1; done

# make check: the framework's tests; Model Builder's, driving its windows
# (under Xvfb when there is no display; one job at a time: its four tools
# share sources, and parallel jobs race to make their object directories); and the SQL stores against the
# servers they are given, each alone and both in one process. A server is
# given by its URL (POSTGRES_URL, MYSQL_URL, MARIADB_URL: a database a test
# may create tables in); without one its suites are skipped, but not in CI,
# where a missing server is a failure.
XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))
check::
	$(MAKE) -C Tests run-tests
	$(MAKE) -j1 -C Tests/ModelBuilder
	$(XVFB) $(MAKE) -j1 -C Tests/ModelBuilder check
	@for server in POSTGRES_URL MYSQL_URL MARIADB_URL; do \
	  if [ -z "$$(printenv $$server)" ]; then \
	    if [ -n "$$CI" ]; then echo "check: $$server is not set; the SQL stores need it in CI"; exit 1; fi; \
	    echo "check: no $$server: its store's suites are skipped"; \
	  fi; \
	done
	@if [ -n "$$POSTGRES_URL" ]; then \
	  CD_TEST_REQUIRE_DATABASE=1 CD_TEST_POSTGRES_URL="$$POSTGRES_URL" $(MAKE) -C Backends/PostgreSQL/Tests run-tests || exit 1; fi
	@if [ -n "$$MYSQL_URL" ]; then \
	  CD_TEST_REQUIRE_DATABASE=1 CD_TEST_MYSQL_URL="$${MYSQL_URL%/*}/cdtest" $(MAKE) -C Backends/MySQL/Tests run-tests || exit 1; fi
	@if [ -n "$$MARIADB_URL" ]; then \
	  CD_TEST_REQUIRE_DATABASE=1 CD_TEST_MYSQL_URL="$${MARIADB_URL%/*}/cdtest" $(MAKE) -C Backends/MySQL/Tests run-tests || exit 1; fi
	@if [ -n "$$POSTGRES_URL" ] && [ -n "$$MYSQL_URL" ]; then \
	  CD_TEST_REQUIRE_DATABASE=1 CD_TEST_POSTGRES_URL="$$POSTGRES_URL" CD_TEST_MYSQL_URL="$${MYSQL_URL%/*}/cdtest" \
	    $(MAKE) -C Backends/Common/Tests run-tests || exit 1; fi
