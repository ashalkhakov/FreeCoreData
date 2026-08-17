#include <Foundation/NSString.h>
@interface NSFramework_CoreData : NSObject
+ (NSString *)frameworkVersion;
+ (NSString *const*)frameworkClasses;
@end
@implementation NSFramework_CoreData
+ (NSString *)frameworkVersion { return @"0"; }
static NSString *allClasses[] = {@"NSManagedObjectModel", @"NSEntityDescription", @"NSPropertyDescription", @"NSAttributeDescription", @"NSRelationshipDescription", @"NSFetchedPropertyDescription", @"NSPersistentStoreRequest", @"NSSaveChangesRequest", @"NSFetchRequest", @"NSManagedObject", @"NSManagedObjectID", @"NSManagedObjectContext", @"NSManagedObjectSet", @"NSManagedObjectMutableSet", @"NSManagedObjectSetEnumerator", @"NSPersistentStoreCoordinator", @"NSPersistentStore", @"NSAtomicStore", @"NSIncrementalStore", @"NSIncrementalStoreNode", @"NSAtomicStoreCacheNode", @"NSXMLPersistentStore", @"NSSQLitePersistentStore", @"NSInMemoryPersistentStore", @"NSPropertyMapping", @"NSEntityMapping", @"NSMappingModel", @"NSEntityMigrationPolicy", @"NSMigrationManager", @"NSMergeConflict", @"NSMergePolicy", NULL};
+ (NSString *const*)frameworkClasses { return allClasses; }
@end
