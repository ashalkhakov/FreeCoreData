include $(GNUSTEP_MAKEFILES)/common.make

FRAMEWORK_NAME = CoreData

CoreData_OBJC_FILES = \
	CoreData/CoreDataErrors.m \
	CoreData/NSManagedObjectModel.m \
	CoreData/NSEntityDescription.m \
	CoreData/NSPropertyDescription.m \
	CoreData/NSAttributeDescription.m \
	CoreData/NSRelationshipDescription.m \
	CoreData/NSFetchedPropertyDescription.m \
	CoreData/NSPersistentStoreRequest.m \
	CoreData/NSSaveChangesRequest.m \
	CoreData/NSFetchRequest.m \
	CoreData/NSManagedObject.m \
	CoreData/NSManagedObjectID.m \
	CoreData/NSManagedObjectContext.m \
	CoreData/NSManagedObjectSet.m \
	CoreData/NSManagedObjectMutableSet.m \
	CoreData/NSManagedObjectSetEnumerator.m \
	CoreData/NSPersistentStoreCoordinator.m \
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
	CoreData/NSMappingModel.m \
	CoreData/NSEntityMigrationPolicy.m \
	CoreData/NSMigrationManager.m

CoreData_HEADER_FILES_DIR = CoreData
CoreData_HEADER_FILES_INSTALL_DIR = CoreData

CoreData_HEADER_FILES = \
	CoreData.h \
	CoreDataErrors.h \
	CoreDataExports.h \
	NSAttributeDescription.h \
	NSAtomicStore.h \
	NSAtomicStoreCacheNode.h \
	NSEntityDescription.h \
	NSPersistentStoreRequest.h \
	NSSaveChangesRequest.h \
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
	NSPropertyDescription.h \
	NSRelationshipDescription.h \
	NSSQLitePersistentStore.h \
	NSXMLPersistentStore.h \
	NSPropertyMapping.h \
	NSEntityMapping.h \
	NSMappingModel.h \
	NSEntityMigrationPolicy.h \
	NSMigrationManager.h

CoreData_OBJCFLAGS = -fno-objc-arc

CoreData_LIBRARIES_DEPEND_UPON += -lsqlite3

CoreData_INCLUDE_DIRS = -I.

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/framework.make

-include GNUmakefile.postamble
