/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSSQLitePersistentStore.h"
#import <CoreData/NSIncrementalStoreNode.h>
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <CoreData/NSPersistentStoreRequest.h>
#import <CoreData/NSSaveChangesRequest.h>
#import <CoreData/NSFetchRequest.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectID.h>
#import <CoreData/NSEntityDescription.h>
#import "NSEntityDescription-Private.h"
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import <CoreData/CoreDataErrors.h>
#import "CoreDataUtilities.h"
#import <Foundation/Foundation.h>

#import <sqlite3.h>

#define DATABASE ((sqlite3 *)_database)

/* The value of Z_VERSION written by (and accepted from) this store; the
   same value Apple's SQLite store uses. */
enum { NSSQLitePersistentStoreMetadataVersion=1 };

/* ------------------------------------------------------------------ */
#pragma mark - Naming helpers (Apple-compatible schema names)
/* ------------------------------------------------------------------ */

/* Apple's SQLite store names entity tables Z<ENTITYNAME> and property
   columns Z<PROPERTYNAME>, both uppercased. */
static NSString *columnNameForProperty(NSString *propertyName){
   return [@"Z" stringByAppendingString:[propertyName uppercaseString]];
}

static NSEntityDescription *rootEntity(NSEntityDescription *entity){
   NSEntityDescription *check=entity;

   while([check superentity]!=nil)
    check=[check superentity];

   return check;
}

static NSString *tableNameForEntity(NSEntityDescription *entity){
   return [@"Z" stringByAppendingString:[[rootEntity(entity) name] uppercaseString]];
}

/* Reference objects are the strings "p<Z_PK>", matching the last path
   component of Apple's x-coredata://UUID/Entity/p<Z_PK> object ID URIs. */
static long long primaryKeyFromReferenceObject(id referenceObject){
   NSString *string=[referenceObject description];

   if([string hasPrefix:@"p"])
    string=[string substringFromIndex:1];

   return [string longLongValue];
}

static NSString *referenceObjectForPrimaryKey(long long primaryKey){
   return [NSString stringWithFormat:@"p%lld",primaryKey];
}

/* ------------------------------------------------------------------ */
#pragma mark - SQLite helpers
/* ------------------------------------------------------------------ */

static NSError *sqliteError(sqlite3 *database,NSInteger code,NSString *message){
   NSString *reason=(database!=NULL)?[NSString stringWithUTF8String:sqlite3_errmsg(database)]:@"unknown SQLite error";
   NSString *description=[NSString stringWithFormat:@"%@: %@",message,reason];

   return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
}

static BOOL executeSQL(sqlite3 *database,NSString *sql,NSError **error){
   char *errorMessage=NULL;

   if(sqlite3_exec(database,[sql UTF8String],NULL,NULL,&errorMessage)!=SQLITE_OK){
    if(error!=NULL){
     NSString *reason=(errorMessage!=NULL)?[NSString stringWithUTF8String:errorMessage]:@"unknown SQLite error";

     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@ failed: %@",sql,reason] forKey:NSLocalizedDescriptionKey]];
    }
    if(errorMessage!=NULL)
     sqlite3_free(errorMessage);
    return NO;
   }

   return YES;
}

static sqlite3_stmt *prepareStatement(sqlite3 *database,NSString *sql,NSError **error){
   sqlite3_stmt *statement=NULL;

   if(sqlite3_prepare_v2(database,[sql UTF8String],-1,&statement,NULL)!=SQLITE_OK){
    if(error!=NULL)
     *error=sqliteError(database,NSPersistentStoreOperationError,[NSString stringWithFormat:@"unable to prepare '%@'",sql]);
    return NULL;
   }

   return statement;
}

static BOOL tableExists(sqlite3 *database,NSString *name){
   sqlite3_stmt *statement=prepareStatement(database,@"SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",NULL);
   BOOL          result=NO;

   if(statement==NULL)
    return NO;

   sqlite3_bind_text(statement,1,[name UTF8String],-1,SQLITE_TRANSIENT);
   result=(sqlite3_step(statement)==SQLITE_ROW);
   sqlite3_finalize(statement);

   return result;
}

/* The SQL column type used in CREATE TABLE, mirroring Apple's choices. */
static NSString *sqlTypeForAttribute(NSAttributeDescription *attribute){
   switch([attribute attributeType]){
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSBooleanAttributeType:
     return @"INTEGER";
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
     return @"FLOAT";
    case NSDecimalAttributeType:
     return @"DECIMAL";
    case NSStringAttributeType:
     return @"VARCHAR";
    case NSDateAttributeType:
     return @"TIMESTAMP";
    case NSBinaryDataAttributeType:
    case NSTransformableAttributeType:
    default:
     return @"BLOB";
   }
}

static void bindAttributeValue(sqlite3_stmt *statement,int index,NSAttributeDescription *attribute,id value){
   if(value==nil || value==[NSNull null]){
    sqlite3_bind_null(statement,index);
    return;
   }

   switch([attribute attributeType]){
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
     sqlite3_bind_int64(statement,index,[value longLongValue]);
     break;
    case NSBooleanAttributeType:
     sqlite3_bind_int64(statement,index,[value boolValue]?1:0);
     break;
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
     sqlite3_bind_double(statement,index,[value doubleValue]);
     break;
    case NSDecimalAttributeType:
     sqlite3_bind_text(statement,index,[[value description] UTF8String],-1,SQLITE_TRANSIENT);
     break;
    case NSDateAttributeType:
     sqlite3_bind_double(statement,index,[value timeIntervalSinceReferenceDate]);
     break;
    case NSBinaryDataAttributeType:
     sqlite3_bind_blob(statement,index,[value bytes],(int)[value length],SQLITE_TRANSIENT);
     break;
    case NSTransformableAttributeType:
    default: {
     NSData *data=[NSKeyedArchiver archivedDataWithRootObject:value];

     sqlite3_bind_blob(statement,index,[data bytes],(int)[data length],SQLITE_TRANSIENT);
     break;
    }
    case NSStringAttributeType:
     sqlite3_bind_text(statement,index,[[value description] UTF8String],-1,SQLITE_TRANSIENT);
     break;
   }
}

static id attributeValueFromColumn(sqlite3_stmt *statement,int index,NSAttributeDescription *attribute){
   if(sqlite3_column_type(statement,index)==SQLITE_NULL)
    return nil;

   switch([attribute attributeType]){
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
     return [NSNumber numberWithLongLong:sqlite3_column_int64(statement,index)];
    case NSBooleanAttributeType:
     return [NSNumber numberWithBool:sqlite3_column_int64(statement,index)!=0];
    case NSDoubleAttributeType:
     return [NSNumber numberWithDouble:sqlite3_column_double(statement,index)];
    case NSFloatAttributeType:
     return [NSNumber numberWithFloat:(float)sqlite3_column_double(statement,index)];
    case NSDecimalAttributeType: {
     const unsigned char *text=sqlite3_column_text(statement,index);

     return (text!=NULL)?[NSDecimalNumber decimalNumberWithString:[NSString stringWithUTF8String:(const char *)text]]:nil;
    }
    case NSDateAttributeType:
     return [NSDate dateWithTimeIntervalSinceReferenceDate:sqlite3_column_double(statement,index)];
    case NSBinaryDataAttributeType:
     return [NSData dataWithBytes:sqlite3_column_blob(statement,index) length:sqlite3_column_bytes(statement,index)];
    case NSTransformableAttributeType:
    default: {
     NSData *data=[NSData dataWithBytes:sqlite3_column_blob(statement,index) length:sqlite3_column_bytes(statement,index)];

     return [NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
    case NSStringAttributeType: {
     const unsigned char *text=sqlite3_column_text(statement,index);

     return (text!=NULL)?[NSString stringWithUTF8String:(const char *)text]:nil;
    }
   }
}

/* Reads the store metadata from the Z_METADATA table of an open database.
   Returns nil (with error set) when the table is missing or unreadable. */
static NSDictionary *readMetadata(sqlite3 *database,NSError **error){
   if(!tableExists(database,@"Z_METADATA")){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreInvalidTypeError userInfo:[NSDictionary dictionaryWithObject:@"The file is not a valid CoreData SQLite store (missing Z_METADATA)" forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   sqlite3_stmt *statement=prepareStatement(database,@"SELECT Z_UUID, Z_PLIST FROM Z_METADATA LIMIT 1",error);

   if(statement==NULL)
    return nil;

   NSMutableDictionary *result=[NSMutableDictionary dictionary];

   if(sqlite3_step(statement)==SQLITE_ROW){
    const unsigned char *uuid=sqlite3_column_text(statement,0);
    const void          *plistBytes=sqlite3_column_blob(statement,1);
    int                  plistLength=sqlite3_column_bytes(statement,1);

    if(plistBytes!=NULL && plistLength>0){
     NSData       *plistData=[NSData dataWithBytes:plistBytes length:plistLength];
     NSDictionary *plist=[NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:NULL error:NULL];

     if([plist isKindOfClass:[NSDictionary class]])
      [result addEntriesFromDictionary:plist];
    }

    if(uuid!=NULL)
     [result setObject:[NSString stringWithUTF8String:(const char *)uuid] forKey:NSStoreUUIDKey];
   }

   sqlite3_finalize(statement);

   [result setObject:NSSQLiteStoreType forKey:NSStoreTypeKey];

   return result;
}

/* Writes the store metadata into the Z_METADATA table.  The UUID and type
   are kept out of the property list because they are stored separately
   (UUID) or implied by the store class (type), matching Apple. */
static BOOL writeMetadata(sqlite3 *database,NSDictionary *metadata,NSError **error){
   NSMutableDictionary *plist=[NSMutableDictionary dictionaryWithDictionary:metadata];

   [plist removeObjectForKey:NSStoreUUIDKey];
   [plist removeObjectForKey:NSStoreTypeKey];

   NSData *plistData=[NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];

   if(plistData==nil)
    return NO;

   sqlite3_stmt *statement=prepareStatement(database,@"INSERT OR REPLACE INTO Z_METADATA (Z_VERSION, Z_UUID, Z_PLIST) VALUES (?, ?, ?)",error);

   if(statement==NULL)
    return NO;

   sqlite3_bind_int64(statement,1,NSSQLitePersistentStoreMetadataVersion);
   sqlite3_bind_text(statement,2,[[metadata objectForKey:NSStoreUUIDKey] UTF8String],-1,SQLITE_TRANSIENT);
   sqlite3_bind_blob(statement,3,[plistData bytes],(int)[plistData length],SQLITE_TRANSIENT);

   BOOL result=(sqlite3_step(statement)==SQLITE_DONE);

   sqlite3_finalize(statement);

   if(!result && error!=NULL)
    *error=sqliteError(database,NSPersistentStoreSaveError,@"unable to write store metadata");

   return result;
}

@implementation NSSQLitePersistentStore

/* ------------------------------------------------------------------ */
#pragma mark - Lifecycle and metadata
/* ------------------------------------------------------------------ */

-initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root configurationName:(NSString *)name URL:(NSURL *)url options:(NSDictionary *)options {
   if((self=[super initWithPersistentStoreCoordinator:root configurationName:name URL:url options:options])==nil)
    return nil;

   _database=NULL;
   _entityIDs=[[NSMutableDictionary alloc] init];
   _entityNamesByID=[[NSMutableDictionary alloc] init];

   return self;
}

-(void)dealloc {
   if(_database!=NULL)
    sqlite3_close(DATABASE);
   [_entityIDs release];
   [_entityNamesByID release];
   [super dealloc];
}

+(NSString *)type {
   return NSSQLiteStoreType;
}

-(NSString *)type {
   return NSSQLiteStoreType;
}

+(NSDictionary *)metadataForPersistentStoreWithURL:(NSURL *)url error:(NSError **)error {
   NSString *path=[url path];

   if(path==nil || ![[NSFileManager defaultManager] fileExistsAtPath:path]){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"No SQLite store found at %@",url] forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   sqlite3 *database=NULL;

   if(sqlite3_open_v2([path fileSystemRepresentation],&database,SQLITE_OPEN_READONLY,NULL)!=SQLITE_OK){
    if(error!=NULL)
     *error=sqliteError(database,NSPersistentStoreOpenError,[NSString stringWithFormat:@"unable to open SQLite store at %@",path]);
    if(database!=NULL)
     sqlite3_close(database);
    return nil;
   }

   NSDictionary *result=readMetadata(database,error);

   sqlite3_close(database);

   return result;
}

+(BOOL)setMetadata:(NSDictionary *)metadata forPersistentStoreWithURL:(NSURL *)url error:(NSError **)error {
   NSString *path=[url path];
   sqlite3  *database=NULL;

   if(path==nil || sqlite3_open_v2([path fileSystemRepresentation],&database,SQLITE_OPEN_READWRITE,NULL)!=SQLITE_OK){
    if(error!=NULL)
     *error=sqliteError(database,NSPersistentStoreOpenError,[NSString stringWithFormat:@"unable to open SQLite store at %@",path]);
    if(database!=NULL)
     sqlite3_close(database);
    return NO;
   }

   BOOL result=writeMetadata(database,metadata,error);

   sqlite3_close(database);

   return result;
}

-(void)setMetadata:(NSDictionary *)value {
   [super setMetadata:value];

   /* Apple persists metadata changes to the Z_METADATA table; do so
      immediately so version stamps survive without an explicit save. */
   if(_database!=NULL && tableExists(DATABASE,@"Z_METADATA"))
    writeMetadata(DATABASE,[self metadata],NULL);
}

/* ------------------------------------------------------------------ */
#pragma mark - Entity/schema bookkeeping
/* ------------------------------------------------------------------ */

/* Entities managed by this store: the requested configuration (all model
   entities when the configuration is nil). */
-(NSArray *)_storeEntities {
   NSManagedObjectModel *model=[[self persistentStoreCoordinator] managedObjectModel];

   if([self configurationName]==nil)
    return [model entities];

   return [model entitiesForConfiguration:[self configurationName]];
}

-(void)_registerEntityID:(long long)entityID forName:(NSString *)name {
   NSNumber *number=[NSNumber numberWithLongLong:entityID];

   [_entityIDs setObject:number forKey:name];
   [_entityNamesByID setObject:name forKey:number];
}

-(long long)_entityIDForEntity:(NSEntityDescription *)entity {
   return [[_entityIDs objectForKey:[entity name]] longLongValue];
}

-(NSEntityDescription *)_entityForEntityID:(long long)entityID {
   NSManagedObjectModel *model=[[self persistentStoreCoordinator] managedObjectModel];
   NSString             *name=[_entityNamesByID objectForKey:[NSNumber numberWithLongLong:entityID]];

   if(name==nil)
    return nil;

   return [[model entitiesByName] objectForKey:name];
}

/* Entity IDs of entity and all of its subentities (the Z_ENT values
   sharing the entity's root table). */
-(void)_collectEntityIDsOfEntity:(NSEntityDescription *)entity into:(NSMutableArray *)result {
   [result addObject:[NSNumber numberWithLongLong:[self _entityIDForEntity:entity]]];

   for(NSEntityDescription *subentity in [entity subentities])
    [self _collectEntityIDsOfEntity:subentity into:result];
}

/* Properties of entity including the ones inherited from superentities. */
static void collectPropertiesOfEntityChain(NSEntityDescription *entity,NSMutableDictionary *result){
   for(NSEntityDescription *check=entity;check!=nil;check=[check superentity])
    for(NSPropertyDescription *property in [check properties])
     if([result objectForKey:[property name]]==nil)
      [result setObject:property forKey:[property name]];
}

static NSDictionary *propertiesForEntityChain(NSEntityDescription *entity){
   NSMutableDictionary *result=[NSMutableDictionary dictionary];

   collectPropertiesOfEntityChain(entity,result);

   return result;
}

/* Properties stored in the root table: all properties of every entity in
   the subtree rooted at entity. */
static void collectPropertiesOfEntitySubtree(NSEntityDescription *entity,NSMutableDictionary *result){
   for(NSPropertyDescription *property in [entity properties])
    if([result objectForKey:[property name]]==nil)
     [result setObject:property forKey:[property name]];

   for(NSEntityDescription *subentity in [entity subentities])
    collectPropertiesOfEntitySubtree(subentity,result);
}

/* Describes the join table used by a many-to-many (or inverse-less
   to-many) relationship, from the point of view of the relationship's
   owner.  Both sides of a many-to-many relationship share one table; the
   canonical side is the one with the smaller entity ID (ties broken by
   relationship name). */
-(NSDictionary *)_joinSpecForRelationship:(NSRelationshipDescription *)relationship {
   NSRelationshipDescription *inverse=[relationship inverseRelationship];
   NSEntityDescription       *owner=[relationship entity];
   NSEntityDescription       *destination=[relationship destinationEntity];
   long long                  ownerID=[self _entityIDForEntity:owner];
   long long                  destinationID=[self _entityIDForEntity:destination];
   BOOL                       canonical;

   if(inverse==nil || ![inverse isToMany])
    canonical=YES;
   else if(ownerID!=destinationID)
    canonical=(ownerID<destinationID);
   else
    canonical=([[relationship name] compare:[inverse name]]!=NSOrderedDescending);

   NSRelationshipDescription *canonicalRelationship=canonical?relationship:inverse;
   long long                  canonicalOwnerID=canonical?ownerID:destinationID;

   NSString *table=[NSString stringWithFormat:@"Z_%lld%@",canonicalOwnerID,[[canonicalRelationship name] uppercaseString]];
   NSString *ownerColumn,*destinationColumn;

   /* The column holding an entity's primary keys is named with that
      entity's ID and the name of the relationship pointing at it. */
   if(inverse!=nil)
    ownerColumn=[NSString stringWithFormat:@"Z_%lld%@",ownerID,[[inverse name] uppercaseString]];
   else
    ownerColumn=[NSString stringWithFormat:@"Z_%lld%@",ownerID,[[owner name] uppercaseString]];

   destinationColumn=[NSString stringWithFormat:@"Z_%lld%@",destinationID,[[relationship name] uppercaseString]];

   return [NSDictionary dictionaryWithObjectsAndKeys:table,@"table",ownerColumn,@"ownerColumn",destinationColumn,@"destinationColumn",nil];
}

/* Whether the to-many relationship is stored in a join table (rather than
   as a foreign key on the destination table). */
static BOOL relationshipUsesJoinTable(NSRelationshipDescription *relationship){
   NSRelationshipDescription *inverse=[relationship inverseRelationship];

   return [relationship isToMany] && (inverse==nil || [inverse isToMany]);
}

/* ------------------------------------------------------------------ */
#pragma mark - Schema creation and loading
/* ------------------------------------------------------------------ */

-(BOOL)_createSchema:(NSError **)error {
   NSArray        *entities=[self _storeEntities];
   NSMutableArray *sortedEntities=[NSMutableArray array];
   NSMutableDictionary *entitiesByName=[NSMutableDictionary dictionary];

   for(NSEntityDescription *entity in entities)
    [entitiesByName setObject:entity forKey:[entity name]];

   for(NSString *name in [[entitiesByName allKeys] sortedArrayUsingSelector:@selector(compare:)])
    [sortedEntities addObject:[entitiesByName objectForKey:name]];

   /* Entity IDs are assigned in name order, starting at 1, like Apple. */
   long long nextID=1;

   for(NSEntityDescription *entity in sortedEntities)
    [self _registerEntityID:nextID++ forName:[entity name]];

   if(!executeSQL(DATABASE,@"CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID VARCHAR(255), Z_PLIST BLOB)",error))
    return NO;

   if(!executeSQL(DATABASE,@"CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER)",error))
    return NO;

   for(NSEntityDescription *entity in sortedEntities){
    NSEntityDescription *superentity=[entity superentity];
    long long            superID=(superentity!=nil)?[self _entityIDForEntity:superentity]:0;
    sqlite3_stmt        *statement=prepareStatement(DATABASE,@"INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME, Z_SUPER, Z_MAX) VALUES (?, ?, ?, 0)",error);

    if(statement==NULL)
     return NO;

    sqlite3_bind_int64(statement,1,[self _entityIDForEntity:entity]);
    sqlite3_bind_text(statement,2,[[entity name] UTF8String],-1,SQLITE_TRANSIENT);
    sqlite3_bind_int64(statement,3,superID);

    BOOL ok=(sqlite3_step(statement)==SQLITE_DONE);

    sqlite3_finalize(statement);

    if(!ok){
     if(error!=NULL)
      *error=sqliteError(DATABASE,NSPersistentStoreOperationError,@"unable to populate Z_PRIMARYKEY");
     return NO;
    }
   }

   NSMutableSet *createdJoinTables=[NSMutableSet set];

   for(NSEntityDescription *entity in sortedEntities){
    /* One table per root entity holding the entire entity subtree. */
    if([entity superentity]==nil){
     NSMutableDictionary *properties=[NSMutableDictionary dictionary];
     NSMutableArray      *columns=[NSMutableArray arrayWithObjects:@"Z_PK INTEGER PRIMARY KEY",@"Z_ENT INTEGER",@"Z_OPT INTEGER",nil];

     collectPropertiesOfEntitySubtree(entity,properties);

     for(NSString *name in [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)]){
      NSPropertyDescription *property=[properties objectForKey:name];

      if([property isKindOfClass:[NSAttributeDescription class]])
       [columns addObject:[NSString stringWithFormat:@"\"%@\" %@",columnNameForProperty(name),sqlTypeForAttribute((NSAttributeDescription *)property)]];
      else if([property isKindOfClass:[NSRelationshipDescription class]] && ![(NSRelationshipDescription *)property isToMany])
       [columns addObject:[NSString stringWithFormat:@"\"%@\" INTEGER",columnNameForProperty(name)]];
     }

     NSString *sql=[NSString stringWithFormat:@"CREATE TABLE \"%@\" (%@)",tableNameForEntity(entity),[columns componentsJoinedByString:@", "]];

     if(!executeSQL(DATABASE,sql,error))
      return NO;
    }

    /* Join tables for many-to-many (and inverse-less to-many)
       relationships. */
    for(NSRelationshipDescription *relationship in [[entity relationshipsByName] allValues]){
     if(!relationshipUsesJoinTable(relationship))
      continue;

     NSDictionary *join=[self _joinSpecForRelationship:relationship];
     NSString     *table=[join objectForKey:@"table"];

     if([createdJoinTables containsObject:table])
      continue;
     [createdJoinTables addObject:table];

     NSString *sql=[NSString stringWithFormat:@"CREATE TABLE \"%@\" (\"%@\" INTEGER, \"%@\" INTEGER, PRIMARY KEY (\"%@\", \"%@\"))",table,[join objectForKey:@"ownerColumn"],[join objectForKey:@"destinationColumn"],[join objectForKey:@"ownerColumn"],[join objectForKey:@"destinationColumn"]];

     if(!executeSQL(DATABASE,sql,error))
      return NO;
    }
   }

   return YES;
}

-(BOOL)_loadEntityIDs:(NSError **)error {
   sqlite3_stmt *statement=prepareStatement(DATABASE,@"SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY",error);

   if(statement==NULL)
    return NO;

   while(sqlite3_step(statement)==SQLITE_ROW){
    long long            entityID=sqlite3_column_int64(statement,0);
    const unsigned char *name=sqlite3_column_text(statement,1);

    if(name!=NULL)
     [self _registerEntityID:entityID forName:[NSString stringWithUTF8String:(const char *)name]];
   }

   sqlite3_finalize(statement);

   return YES;
}

-(BOOL)loadMetadata:(NSError **)error {
   NSString *path=[[self URL] path];

   if(path==nil){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreInvalidTypeError userInfo:[NSDictionary dictionaryWithObject:@"NSSQLiteStoreType requires a file URL" forKey:NSLocalizedDescriptionKey]];
    return NO;
   }

   sqlite3 *database=NULL;

   if(sqlite3_open([path fileSystemRepresentation],&database)!=SQLITE_OK){
    if(error!=NULL)
     *error=sqliteError(database,NSPersistentStoreOpenError,[NSString stringWithFormat:@"unable to open SQLite store at %@",path]);
    if(database!=NULL)
     sqlite3_close(database);
    return NO;
   }

   _database=database;

   if(tableExists(DATABASE,@"Z_METADATA")){
    NSDictionary *metadata=readMetadata(DATABASE,error);

    if(metadata==nil)
     return NO;

    [super setMetadata:metadata];

    return [self _loadEntityIDs:error];
   }

   /* New (or empty) file: create the schema and stamp the metadata with
      the version hashes of the model in use, so compatibility can be
      checked when the store is reopened later. */
   if(!executeSQL(DATABASE,@"BEGIN",error))
    return NO;

   if(![self _createSchema:error]){
    executeSQL(DATABASE,@"ROLLBACK",NULL);
    return NO;
   }

   NSManagedObjectModel *model=[[self persistentStoreCoordinator] managedObjectModel];
   NSMutableDictionary  *versionHashes=[NSMutableDictionary dictionary];

   for(NSEntityDescription *entity in [self _storeEntities])
    [versionHashes setObject:[entity versionHash] forKey:[entity name]];

   NSDictionary *metadata=[NSDictionary dictionaryWithObjectsAndKeys:
                              NSSQLiteStoreType,NSStoreTypeKey,
                              [[NSUUID UUID] UUIDString],NSStoreUUIDKey,
                              versionHashes,NSStoreModelVersionHashesKey,
                              [[model versionIdentifiers] allObjects],NSStoreModelVersionIdentifiersKey,
                              nil];

   [super setMetadata:metadata];

   if(!writeMetadata(DATABASE,metadata,error)){
    executeSQL(DATABASE,@"ROLLBACK",NULL);
    return NO;
   }

   if(!executeSQL(DATABASE,@"COMMIT",error)){
    executeSQL(DATABASE,@"ROLLBACK",NULL);
    return NO;
   }

   return YES;
}

/* ------------------------------------------------------------------ */
#pragma mark - Predicate and sort-descriptor translation
/* ------------------------------------------------------------------ */

/* Like Apple's SQLite store, fetch predicates and sort descriptors are
   translated to SQL and evaluated by SQLite whenever possible.  The
   translator is conservative: any construct whose SQL semantics would not
   exactly match in-memory evaluation makes the translation fail, and the
   store falls back to filtering/sorting the fetched objects in memory. */

/* Bound parameters produced by the translator: each entry carries the
   value and the property it is compared against (so attribute values are
   bound with the correct SQLite type). */
static NSDictionary *predicateBinding(NSPropertyDescription *property,id value){
   return [NSDictionary dictionaryWithObjectsAndKeys:value,@"value",property,@"property",nil];
}

static void bindPredicateValue(sqlite3_stmt *statement,int index,NSDictionary *binding){
   NSPropertyDescription *property=[binding objectForKey:@"property"];
   id                     value=[binding objectForKey:@"value"];

   if([property isKindOfClass:[NSAttributeDescription class]])
    bindAttributeValue(statement,index,(NSAttributeDescription *)property,value);
   else /* to-one relationship: value is the destination's Z_PK. */
    sqlite3_bind_int64(statement,index,[value longLongValue]);
}

/* Bound parameters are limited by SQLITE_LIMIT_VARIABLE_NUMBER (999 in
   older SQLite builds); IN collections beyond this size are evaluated in
   memory instead of being batched. */
enum { NSSQLitePersistentStoreMaxInListSize=900 };

/* Attribute types whose stored representation compares exactly like the
   in-memory value.  Decimals are stored as text (lexicographic order) and
   binary/transformable values as non-canonical blobs, so predicates and
   sort descriptors on them are evaluated in memory. */
static BOOL attributeComparesExactlyInSQL(NSAttributeDescription *attribute){
   switch([attribute attributeType]){
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSBooleanAttributeType:
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
    case NSDateAttributeType:
    case NSStringAttributeType:
     return YES;
    default:
     return NO;
   }
}

static NSString *escapedLikePattern(NSString *string){
   NSMutableString *result=[NSMutableString stringWithString:string];

   [result replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0,[result length])];
   [result replaceOccurrencesOfString:@"%" withString:@"\\%" options:0 range:NSMakeRange(0,[result length])];
   [result replaceOccurrencesOfString:@"_" withString:@"\\_" options:0 range:NSMakeRange(0,[result length])];

   return result;
}

static NSString *escapedGlobPattern(NSString *string){
   NSMutableString *result=[NSMutableString stringWithString:string];

   [result replaceOccurrencesOfString:@"[" withString:@"[[]" options:0 range:NSMakeRange(0,[result length])];
   [result replaceOccurrencesOfString:@"*" withString:@"[*]" options:0 range:NSMakeRange(0,[result length])];
   [result replaceOccurrencesOfString:@"?" withString:@"[?]" options:0 range:NSMakeRange(0,[result length])];

   return result;
}

/* Wildcard-match clause: SQLite LIKE is (ASCII) case-insensitive, GLOB is
   case-sensitive, so [c] matches map to LIKE and exact ones to GLOB.
   prefix/suffix are the unescaped wildcards surrounding the constant. */
static NSString *patternMatchClause(NSString *column,NSString *constant,BOOL caseInsensitive,NSString *prefix,NSString *suffix,NSMutableArray *bindings,NSAttributeDescription *attribute){
   NSString *pattern;

   if(caseInsensitive){
    pattern=[NSString stringWithFormat:@"%@%@%@",prefix,escapedLikePattern(constant),suffix];
    [bindings addObject:predicateBinding(attribute,pattern)];
    return [NSString stringWithFormat:@"%@ LIKE ? ESCAPE '\\'",column];
   }

   pattern=[NSString stringWithFormat:@"%@%@%@",[prefix isEqualToString:@"%"]?@"*":@"",escapedGlobPattern(constant),[suffix isEqualToString:@"%"]?@"*":@""];
   [bindings addObject:predicateBinding(attribute,pattern)];
   return [NSString stringWithFormat:@"%@ GLOB ?",column];
}

/* Returns the Z_PK of a to-one relationship constant (an NSManagedObject
   or NSManagedObjectID belonging to this store), or nil when the value
   cannot be resolved to a row of this store. */
-(NSNumber *)_primaryKeyForRelationshipConstant:(id)value {
   NSManagedObjectID *objectID=nil;

   if([value isKindOfClass:[NSManagedObjectID class]])
    objectID=value;
   else if([value isKindOfClass:[NSManagedObject class]])
    objectID=[value objectID];
   else
    return nil;

   if([objectID isTemporaryID] || [objectID persistentStore]!=self)
    return nil;

   return [NSNumber numberWithLongLong:primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID])];
}

/* Some NSPredicate implementations (e.g. GNUstep base) hand back constant
   values still wrapped in constant NSExpressions; unwrap them. */
static id resolvedConstantValue(id value){
   while([value isKindOfClass:[NSExpression class]] &&
         [(NSExpression *)value expressionType]==NSConstantValueExpressionType)
    value=[(NSExpression *)value constantValue];

   return value;
}

/* The elements of an IN/BETWEEN right-hand side as plain constant values,
   accepting constant collections as well as aggregate expressions.
   Returns nil when any element is not a constant. */
static NSArray *constantCollectionFromExpression(NSExpression *expression){
   id raw=nil;

   if([expression expressionType]==NSConstantValueExpressionType)
    raw=[expression constantValue];
   else if([expression respondsToSelector:@selector(collection)])
    raw=[expression performSelector:@selector(collection)];

   if(![raw isKindOfClass:[NSArray class]] && ![raw isKindOfClass:[NSSet class]])
    return nil;

   NSMutableArray *result=[NSMutableArray array];

   for(id element in raw){
    id value=resolvedConstantValue(element);

    if(value==nil || value==[NSNull null] || [value isKindOfClass:[NSExpression class]])
     return nil;

    [result addObject:value];
   }

   return result;
}

-(NSString *)_translateComparisonPredicate:(NSComparisonPredicate *)comparison entity:(NSEntityDescription *)entity bindings:(NSMutableArray *)bindings {
   if([comparison comparisonPredicateModifier]!=NSDirectPredicateModifier)
    return nil;

   NSComparisonPredicateOptions options=[comparison options];

   /* Only exact and [c] matches translate exactly; diacritic- or
      locale-sensitive matching happens in memory. */
   if((options&~NSCaseInsensitivePredicateOption)!=0)
    return nil;

   BOOL caseInsensitive=(options&NSCaseInsensitivePredicateOption)!=0;

   NSExpression *lhs=[comparison leftExpression];
   NSExpression *rhs=[comparison rightExpression];
   NSPredicateOperatorType operator=[comparison predicateOperatorType];

   /* Normalize to <keypath> <operator> <constant>, flipping the operator
      when the predicate was written the other way around. */
   if([lhs expressionType]==NSConstantValueExpressionType && [rhs expressionType]==NSKeyPathExpressionType){
    NSExpression *swap=lhs; lhs=rhs; rhs=swap;

    switch(operator){
     case NSLessThanPredicateOperatorType:            operator=NSGreaterThanPredicateOperatorType; break;
     case NSLessThanOrEqualToPredicateOperatorType:   operator=NSGreaterThanOrEqualToPredicateOperatorType; break;
     case NSGreaterThanPredicateOperatorType:         operator=NSLessThanPredicateOperatorType; break;
     case NSGreaterThanOrEqualToPredicateOperatorType:operator=NSLessThanOrEqualToPredicateOperatorType; break;
     case NSEqualToPredicateOperatorType:
     case NSNotEqualToPredicateOperatorType:
      break;
     default:
      return nil;
    }
   }

   if([lhs expressionType]!=NSKeyPathExpressionType)
    return nil;

   BOOL rhsIsCollection=(operator==NSInPredicateOperatorType || operator==NSBetweenPredicateOperatorType);

   if(!rhsIsCollection && [rhs expressionType]!=NSConstantValueExpressionType)
    return nil;

   NSString *keyPath=[lhs keyPath];

   /* Key paths crossing relationships would need SQL joins. */
   if([keyPath rangeOfString:@"."].location!=NSNotFound)
    return nil;

   NSPropertyDescription *property=[propertiesForEntityChain(entity) objectForKey:keyPath];
   id                     constant=rhsIsCollection?nil:resolvedConstantValue([rhs constantValue]);

   if(constant==[NSNull null])
    constant=nil;
   if([constant isKindOfClass:[NSExpression class]])
    return nil;

   NSString *column=[NSString stringWithFormat:@"\"%@\"",columnNameForProperty(keyPath)];

   /* To-one relationships compare against the destination row's Z_PK. */
   if([property isKindOfClass:[NSRelationshipDescription class]]){
    NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;

    if([relationship isToMany])
     return nil;
    if(operator!=NSEqualToPredicateOperatorType && operator!=NSNotEqualToPredicateOperatorType)
     return nil;

    if(constant==nil)
     return [NSString stringWithFormat:@"%@ IS %@NULL",column,(operator==NSEqualToPredicateOperatorType)?@"":@"NOT "];

    NSNumber *primaryKey=[self _primaryKeyForRelationshipConstant:constant];

    if(primaryKey==nil)
     return nil;

    [bindings addObject:predicateBinding(relationship,primaryKey)];
    return [NSString stringWithFormat:@"%@ %@ ?",column,(operator==NSEqualToPredicateOperatorType)?@"=":@"<>"];
   }

   if(![property isKindOfClass:[NSAttributeDescription class]])
    return nil;

   NSAttributeDescription *attribute=(NSAttributeDescription *)property;

   if(!attributeComparesExactlyInSQL(attribute))
    return nil;

   /* String matching against attributes stored as text only. */
   switch(operator){
    case NSLikePredicateOperatorType:
    case NSBeginsWithPredicateOperatorType:
    case NSEndsWithPredicateOperatorType:
    case NSContainsPredicateOperatorType:
     if([attribute attributeType]!=NSStringAttributeType || ![constant isKindOfClass:[NSString class]])
      return nil;
     break;
    default:
     break;
   }

   NSString *collate=caseInsensitive?@" COLLATE NOCASE":@"";

   switch(operator){

    case NSEqualToPredicateOperatorType:
     if(constant==nil)
      return [NSString stringWithFormat:@"%@ IS NULL",column];
     [bindings addObject:predicateBinding(attribute,constant)];
     return [NSString stringWithFormat:@"%@ = ?%@",column,collate];

    case NSNotEqualToPredicateOperatorType:
     if(constant==nil)
      return [NSString stringWithFormat:@"%@ IS NOT NULL",column];
     /* Like Apple's SQLite store, NULL rows do not match a != constant
        comparison (SQL NULL semantics). */
     [bindings addObject:predicateBinding(attribute,constant)];
     return [NSString stringWithFormat:@"%@ <> ?%@",column,collate];

    case NSLessThanPredicateOperatorType:
    case NSLessThanOrEqualToPredicateOperatorType:
    case NSGreaterThanPredicateOperatorType:
    case NSGreaterThanOrEqualToPredicateOperatorType: {
     if(constant==nil || caseInsensitive)
      return nil;

     NSString *operatorSQL=(operator==NSLessThanPredicateOperatorType)?@"<":
                           (operator==NSLessThanOrEqualToPredicateOperatorType)?@"<=":
                           (operator==NSGreaterThanPredicateOperatorType)?@">":@">=";

     [bindings addObject:predicateBinding(attribute,constant)];
     return [NSString stringWithFormat:@"%@ %@ ?",column,operatorSQL];
    }

    case NSInPredicateOperatorType: {
     if(caseInsensitive)
      return nil;

     NSArray *elements=constantCollectionFromExpression(rhs);

     if(elements==nil)
      return nil;

     NSUInteger count=[elements count];

     if(count==0)
      return @"0";
     if(count>NSSQLitePersistentStoreMaxInListSize)
      return nil;

     NSMutableArray *placeholders=[NSMutableArray array];

     for(id element in elements){
      [bindings addObject:predicateBinding(attribute,element)];
      [placeholders addObject:@"?"];
     }

     return [NSString stringWithFormat:@"%@ IN (%@)",column,[placeholders componentsJoinedByString:@", "]];
    }

    case NSBetweenPredicateOperatorType: {
     if(caseInsensitive)
      return nil;

     NSArray *elements=constantCollectionFromExpression(rhs);

     if([elements count]!=2)
      return nil;

     [bindings addObject:predicateBinding(attribute,[elements objectAtIndex:0])];
     [bindings addObject:predicateBinding(attribute,[elements objectAtIndex:1])];
     return [NSString stringWithFormat:@"%@ BETWEEN ? AND ?",column];
    }

    case NSBeginsWithPredicateOperatorType:
     return patternMatchClause(column,constant,caseInsensitive,@"",@"%",bindings,attribute);

    case NSEndsWithPredicateOperatorType:
     return patternMatchClause(column,constant,caseInsensitive,@"%",@"",bindings,attribute);

    case NSContainsPredicateOperatorType:
     return patternMatchClause(column,constant,caseInsensitive,@"%",@"%",bindings,attribute);

    case NSLikePredicateOperatorType: {
     /* NSPredicate LIKE wildcards: * (any sequence) and ? (any single
        character). */
     if(caseInsensitive){
      NSMutableString *pattern=[NSMutableString stringWithString:escapedLikePattern(constant)];

      [pattern replaceOccurrencesOfString:@"*" withString:@"%" options:0 range:NSMakeRange(0,[pattern length])];
      [pattern replaceOccurrencesOfString:@"?" withString:@"_" options:0 range:NSMakeRange(0,[pattern length])];
      [bindings addObject:predicateBinding(attribute,pattern)];
      return [NSString stringWithFormat:@"%@ LIKE ? ESCAPE '\\'",column];
     }

     NSMutableString *pattern=[NSMutableString stringWithString:constant];

     [pattern replaceOccurrencesOfString:@"[" withString:@"[[]" options:0 range:NSMakeRange(0,[pattern length])];
     [bindings addObject:predicateBinding(attribute,pattern)];
     return [NSString stringWithFormat:@"%@ GLOB ?",column];
    }

    default:
     return nil;
   }
}

/* Translates predicate into a SQL boolean expression over entity's table,
   appending the bound parameter values to bindings.  Returns nil when the
   predicate contains constructs that cannot be translated exactly. */
-(NSString *)_translatePredicate:(NSPredicate *)predicate entity:(NSEntityDescription *)entity bindings:(NSMutableArray *)bindings {
   if([predicate isKindOfClass:[NSCompoundPredicate class]]){
    NSCompoundPredicate *compound=(NSCompoundPredicate *)predicate;
    NSArray             *subpredicates=[compound subpredicates];
    NSMutableArray      *clauses=[NSMutableArray array];

    for(NSPredicate *subpredicate in subpredicates){
     NSString *clause=[self _translatePredicate:subpredicate entity:entity bindings:bindings];

     if(clause==nil)
      return nil;

     [clauses addObject:clause];
    }

    switch([compound compoundPredicateType]){
     case NSNotPredicateType:
      if([clauses count]!=1)
       return nil;
      return [NSString stringWithFormat:@"NOT (%@)",[clauses objectAtIndex:0]];
     case NSAndPredicateType:
      if([clauses count]==0)
       return @"1"; /* empty AND is true */
      return [NSString stringWithFormat:@"(%@)",[clauses componentsJoinedByString:@" AND "]];
     case NSOrPredicateType:
      if([clauses count]==0)
       return @"0"; /* empty OR is false */
      return [NSString stringWithFormat:@"(%@)",[clauses componentsJoinedByString:@" OR "]];
     default:
      return nil;
    }
   }

   if([predicate isKindOfClass:[NSComparisonPredicate class]])
    return [self _translateComparisonPredicate:(NSComparisonPredicate *)predicate entity:entity bindings:bindings];

   /* Constant predicates ([NSPredicate predicateWithValue:]). */
   if([predicate isEqual:[NSPredicate predicateWithValue:YES]])
    return @"1";
   if([predicate isEqual:[NSPredicate predicateWithValue:NO]])
    return @"0";

   return nil;
}

/* Translates the sort descriptors into an ORDER BY fragment, or nil when
   a descriptor cannot be evaluated by SQLite exactly. */
-(NSString *)_translateSortDescriptors:(NSArray *)sortDescriptors entity:(NSEntityDescription *)entity {
   NSMutableArray *terms=[NSMutableArray array];

   for(NSSortDescriptor *descriptor in sortDescriptors){
    NSString *key=[descriptor key];

    if(key==nil || [key rangeOfString:@"."].location!=NSNotFound)
     return nil;

    NSPropertyDescription *property=[propertiesForEntityChain(entity) objectForKey:key];

    if(![property isKindOfClass:[NSAttributeDescription class]] || !attributeComparesExactlyInSQL((NSAttributeDescription *)property))
     return nil;

    SEL       selector=[descriptor selector];
    NSString *selectorName=(selector!=NULL)?NSStringFromSelector(selector):nil;
    NSString *collate;

    if(selectorName==nil || [selectorName isEqualToString:@"compare:"])
     collate=@"";
    else if([selectorName isEqualToString:@"caseInsensitiveCompare:"])
     collate=@" COLLATE NOCASE";
    else
     return nil;

    [terms addObject:[NSString stringWithFormat:@"\"%@\"%@ %@",columnNameForProperty(key),collate,[descriptor ascending]?@"ASC":@"DESC"]];
   }

   return [terms componentsJoinedByString:@", "];
}

/* ------------------------------------------------------------------ */
#pragma mark - Fetching
/* ------------------------------------------------------------------ */

-(NSArray *)_fetchObjectIDsForEntity:(NSEntityDescription *)entity includesSubentities:(BOOL)includesSubentities whereSQL:(NSString *)whereSQL bindings:(NSArray *)bindings orderBySQL:(NSString *)orderBySQL fetchLimit:(NSUInteger)fetchLimit fetchOffset:(NSUInteger)fetchOffset error:(NSError **)error {
   if([_entityIDs objectForKey:[entity name]]==nil)
    return [NSArray array];

   NSMutableArray *entityIDs=[NSMutableArray array];

   if(includesSubentities)
    [self _collectEntityIDsOfEntity:entity into:entityIDs];
   else
    [entityIDs addObject:[NSNumber numberWithLongLong:[self _entityIDForEntity:entity]]];

   /* The Z_ENT list holds one trusted integer literal per entity in the
      model subtree, so it is bounded by the model size (and by
      SQLITE_MAX_SQL_LENGTH, not the bound-parameter limit); it never
      needs batching. */
   NSString *sql=[NSString stringWithFormat:@"SELECT Z_PK, Z_ENT FROM \"%@\" WHERE Z_ENT IN (%@)",tableNameForEntity(entity),[entityIDs componentsJoinedByString:@", "]];

   if(whereSQL!=nil)
    sql=[sql stringByAppendingFormat:@" AND (%@)",whereSQL];

   if([orderBySQL length]>0)
    sql=[sql stringByAppendingFormat:@" ORDER BY %@, Z_PK",orderBySQL];
   else
    sql=[sql stringByAppendingString:@" ORDER BY Z_PK"];

   if(fetchLimit>0 || fetchOffset>0)
    sql=[sql stringByAppendingFormat:@" LIMIT %lld OFFSET %llu",fetchLimit>0?(long long)fetchLimit:-1LL,(unsigned long long)fetchOffset];

   sqlite3_stmt *statement=prepareStatement(DATABASE,sql,error);

   if(statement==NULL)
    return nil;

   int parameterIndex=1;

   for(NSDictionary *binding in bindings)
    bindPredicateValue(statement,parameterIndex++,binding);

   NSMutableArray *result=[NSMutableArray array];

   while(sqlite3_step(statement)==SQLITE_ROW){
    long long            primaryKey=sqlite3_column_int64(statement,0);
    long long            entityID=sqlite3_column_int64(statement,1);
    NSEntityDescription *rowEntity=[self _entityForEntityID:entityID];

    if(rowEntity==nil)
     rowEntity=entity;

    [result addObject:[[self newObjectIDForEntity:rowEntity referenceObject:referenceObjectForPrimaryKey(primaryKey)] autorelease]];
   }

   sqlite3_finalize(statement);

   return result;
}

-(id)_executeFetchRequest:(NSFetchRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSEntityDescription *entity=[request entity];

   /* Predicates and sort descriptors are translated to SQL when possible;
      anything that would not translate exactly is evaluated in memory.
      The offset/limit can only be pushed down to SQLite when nothing is
      evaluated in memory (otherwise it would change the result). */
   NSMutableArray *bindings=[NSMutableArray array];
   NSString       *whereSQL=nil;
   BOOL            predicateInSQL=YES;

   if([request predicate]!=nil){
    whereSQL=[self _translatePredicate:[request predicate] entity:entity bindings:bindings];
    predicateInSQL=(whereSQL!=nil);

    if(!predicateInSQL)
     [bindings removeAllObjects];
   }

   NSString *orderBySQL=nil;
   BOOL      sortsInSQL=YES;

   if([[request sortDescriptors] count]>0){
    orderBySQL=[self _translateSortDescriptors:[request sortDescriptors] entity:entity];
    sortsInSQL=(orderBySQL!=nil);
   }

   BOOL       filtersInMemory=(!predicateInSQL || !sortsInSQL);
   NSUInteger sqlLimit=filtersInMemory?0:[request fetchLimit];
   NSUInteger sqlOffset=filtersInMemory?0:[request fetchOffset];

   NSArray *objectIDs=[self _fetchObjectIDsForEntity:entity includesSubentities:[request includesSubentities] whereSQL:whereSQL bindings:bindings orderBySQL:orderBySQL fetchLimit:sqlLimit fetchOffset:sqlOffset error:error];

   if(objectIDs==nil)
    return nil;

   NSMutableArray *objects=[NSMutableArray array];

   for(NSManagedObjectID *objectID in objectIDs)
    [objects addObject:[context objectWithID:objectID]];

   if([request predicate]!=nil && !predicateInSQL)
    [objects filterUsingPredicate:[request predicate]];

   /* Filtering preserves order, so a SQL-applied sort survives in-memory
      predicate evaluation. */
   if([[request sortDescriptors] count]>0 && !sortsInSQL)
    [objects sortUsingDescriptors:[request sortDescriptors]];

   if(filtersInMemory){
    NSUInteger offset=[request fetchOffset];
    NSUInteger limit=[request fetchLimit];

    if(offset>0){
     if(offset>=[objects count])
      [objects removeAllObjects];
     else
      [objects removeObjectsInRange:NSMakeRange(0,offset)];
    }

    if(limit>0 && [objects count]>limit)
     [objects removeObjectsInRange:NSMakeRange(limit,[objects count]-limit)];
   }

   if([request resultType]==NSManagedObjectIDResultType){
    NSMutableArray *result=[NSMutableArray array];

    for(NSManagedObject *object in objects)
     [result addObject:[object objectID]];

    return result;
   }

   return objects;
}

/* ------------------------------------------------------------------ */
#pragma mark - Saving
/* ------------------------------------------------------------------ */

/* Updates the join table and foreign-key backed to-many relationships of
   object so that they match the object's in-memory state. */
-(BOOL)_writeToManyRelationshipsForObject:(NSManagedObject *)object error:(NSError **)error {
   NSEntityDescription *entity=[object entity];
   NSDictionary        *properties=propertiesForEntityChain(entity);
   long long            primaryKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:[object objectID]]);

   for(NSString *name in properties){
    NSPropertyDescription *property=[properties objectForKey:name];

    if(![property isKindOfClass:[NSRelationshipDescription class]])
     continue;

    NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;

    if(![relationship isToMany])
     continue;

    id members=[object valueForKey:name];

    if(relationshipUsesJoinTable(relationship)){
     NSDictionary *join=[self _joinSpecForRelationship:relationship];

     NSString *deleteSQL=[NSString stringWithFormat:@"DELETE FROM \"%@\" WHERE \"%@\" = %lld",[join objectForKey:@"table"],[join objectForKey:@"ownerColumn"],primaryKey];

     if(!executeSQL(DATABASE,deleteSQL,error))
      return NO;

     for(NSManagedObject *member in members){
      long long memberKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:[member objectID]]);
      NSString *insertSQL=[NSString stringWithFormat:@"INSERT OR REPLACE INTO \"%@\" (\"%@\", \"%@\") VALUES (%lld, %lld)",[join objectForKey:@"table"],[join objectForKey:@"ownerColumn"],[join objectForKey:@"destinationColumn"],primaryKey,memberKey];

      if(!executeSQL(DATABASE,insertSQL,error))
       return NO;
     }
    }
    else {
     /* Foreign key on the destination table (inverse is to-one). */
     NSRelationshipDescription *inverse=[relationship inverseRelationship];
     NSString                  *destinationTable=tableNameForEntity([relationship destinationEntity]);
     NSString                  *foreignKeyColumn=columnNameForProperty([inverse name]);

     NSString *clearSQL=[NSString stringWithFormat:@"UPDATE \"%@\" SET \"%@\" = NULL WHERE \"%@\" = %lld",destinationTable,foreignKeyColumn,foreignKeyColumn,primaryKey];

     if(!executeSQL(DATABASE,clearSQL,error))
      return NO;

     for(NSManagedObject *member in members){
      long long memberKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:[member objectID]]);
      NSString *setSQL=[NSString stringWithFormat:@"UPDATE \"%@\" SET \"%@\" = %lld WHERE Z_PK = %lld",destinationTable,foreignKeyColumn,primaryKey,memberKey];

      if(!executeSQL(DATABASE,setSQL,error))
       return NO;
     }
    }
   }

   return YES;
}

-(BOOL)_writeRowForObject:(NSManagedObject *)object isInsert:(BOOL)isInsert error:(NSError **)error {
   NSEntityDescription *entity=[object entity];
   NSDictionary        *properties=propertiesForEntityChain(entity);
   long long            primaryKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:[object objectID]]);
   NSMutableArray      *names=[NSMutableArray array];
   NSMutableArray      *values=[NSMutableArray array]; /* NSNull placeholders keep indexes aligned */
   NSMutableArray      *boundProperties=[NSMutableArray array];

   for(NSString *name in [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)]){
    NSPropertyDescription *property=[properties objectForKey:name];
    id                     value=nil;

    if([property isKindOfClass:[NSAttributeDescription class]])
     value=[object valueForKey:name];
    else if([property isKindOfClass:[NSRelationshipDescription class]] && ![(NSRelationshipDescription *)property isToMany]){
     NSManagedObject *destination=[object valueForKey:name];

     if(destination!=nil)
      value=[NSNumber numberWithLongLong:primaryKeyFromReferenceObject([self referenceObjectForObjectID:[destination objectID]])];
    }
    else
     continue;

    [names addObject:columnNameForProperty(name)];
    [values addObject:(value!=nil)?value:(id)[NSNull null]];
    [boundProperties addObject:property];
   }

   NSString *sql;

   if(isInsert){
    NSMutableArray *columns=[NSMutableArray arrayWithObjects:@"Z_PK",@"Z_ENT",@"Z_OPT",nil];
    NSMutableArray *placeholders=[NSMutableArray arrayWithObjects:@"?",@"?",@"?",nil];

    for(NSString *name in names){
     [columns addObject:[NSString stringWithFormat:@"\"%@\"",name]];
     [placeholders addObject:@"?"];
    }

    sql=[NSString stringWithFormat:@"INSERT INTO \"%@\" (%@) VALUES (%@)",tableNameForEntity(entity),[columns componentsJoinedByString:@", "],[placeholders componentsJoinedByString:@", "]];
   }
   else {
    NSMutableArray *assignments=[NSMutableArray arrayWithObject:@"Z_OPT = Z_OPT + 1"];

    for(NSString *name in names)
     [assignments addObject:[NSString stringWithFormat:@"\"%@\" = ?",name]];

    sql=[NSString stringWithFormat:@"UPDATE \"%@\" SET %@ WHERE Z_PK = %lld",tableNameForEntity(entity),[assignments componentsJoinedByString:@", "],primaryKey];
   }

   sqlite3_stmt *statement=prepareStatement(DATABASE,sql,error);

   if(statement==NULL)
    return NO;

   int index=1;

   if(isInsert){
    sqlite3_bind_int64(statement,index++,primaryKey);
    sqlite3_bind_int64(statement,index++,[self _entityIDForEntity:entity]);
    sqlite3_bind_int64(statement,index++,1);
   }

   NSUInteger i,count=[names count];

   for(i=0;i<count;i++){
    NSPropertyDescription *property=[boundProperties objectAtIndex:i];
    id                     value=[values objectAtIndex:i];

    if(value==[NSNull null])
     sqlite3_bind_null(statement,index++);
    else if([property isKindOfClass:[NSAttributeDescription class]])
     bindAttributeValue(statement,index++,(NSAttributeDescription *)property,value);
    else
     sqlite3_bind_int64(statement,index++,[value longLongValue]);
   }

   BOOL result=(sqlite3_step(statement)==SQLITE_DONE);

   sqlite3_finalize(statement);

   if(!result){
    if(error!=NULL)
     *error=sqliteError(DATABASE,NSPersistentStoreSaveError,[NSString stringWithFormat:@"unable to save %@",[entity name]]);
    return NO;
   }

   return [self _writeToManyRelationshipsForObject:object error:error];
}

-(BOOL)_deleteRowForObject:(NSManagedObject *)object error:(NSError **)error {
   NSEntityDescription *entity=[object entity];
   NSDictionary        *properties=propertiesForEntityChain(entity);
   long long            primaryKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:[object objectID]]);

   /* Clean up any join-table rows referencing the deleted row.  Rows
      where the object is the relationship's owner are found through its
      own relationships; rows where it is the destination of another
      entity's inverse-less to-many relationship must be swept from that
      relationship's side. */
   for(NSString *name in properties){
    NSPropertyDescription *property=[properties objectForKey:name];

    if(![property isKindOfClass:[NSRelationshipDescription class]])
     continue;

    NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;

    if(relationshipUsesJoinTable(relationship)){
     NSDictionary *join=[self _joinSpecForRelationship:relationship];
     NSString     *sql=[NSString stringWithFormat:@"DELETE FROM \"%@\" WHERE \"%@\" = %lld",[join objectForKey:@"table"],[join objectForKey:@"ownerColumn"],primaryKey];

     if(!executeSQL(DATABASE,sql,error))
      return NO;
    }
   }

   for(NSEntityDescription *check in [self _storeEntities]){
    for(NSRelationshipDescription *relationship in [[check relationshipsByName] allValues]){
     if(!relationshipUsesJoinTable(relationship) || [relationship inverseRelationship]!=nil)
      continue;
     if(![entity _isKindOfEntity:[relationship destinationEntity]] && ![[relationship destinationEntity] _isKindOfEntity:entity])
      continue;

     NSDictionary *join=[self _joinSpecForRelationship:relationship];
     NSString     *sql=[NSString stringWithFormat:@"DELETE FROM \"%@\" WHERE \"%@\" = %lld",[join objectForKey:@"table"],[join objectForKey:@"destinationColumn"],primaryKey];

     if(!executeSQL(DATABASE,sql,error))
      return NO;
    }
   }

   NSString *sql=[NSString stringWithFormat:@"DELETE FROM \"%@\" WHERE Z_PK = %lld",tableNameForEntity(entity),primaryKey];

   return executeSQL(DATABASE,sql,error);
}

-(id)_executeSaveRequest:(NSSaveChangesRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   if(!executeSQL(DATABASE,@"BEGIN",error))
    return nil;

   for(NSManagedObject *object in [request insertedObjects]){
    if(![self _writeRowForObject:object isInsert:YES error:error]){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }
   }

   for(NSManagedObject *object in [request updatedObjects]){
    if(![self _writeRowForObject:object isInsert:NO error:error]){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }
   }

   for(NSManagedObject *object in [request deletedObjects]){
    if(![self _deleteRowForObject:object error:error]){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }
   }

   if(!writeMetadata(DATABASE,[self metadata],error)){
    executeSQL(DATABASE,@"ROLLBACK",NULL);
    return nil;
   }

   if(!executeSQL(DATABASE,@"COMMIT",error)){
    executeSQL(DATABASE,@"ROLLBACK",NULL);
    return nil;
   }

   return [NSArray array];
}

-(id)executeRequest:(NSPersistentStoreRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   if([request requestType]==NSFetchRequestType)
    return [self _executeFetchRequest:(NSFetchRequest *)request withContext:context error:error];

   if([request requestType]==NSSaveRequestType)
    return [self _executeSaveRequest:(NSSaveChangesRequest *)request withContext:context error:error];

   if(error!=NULL)
    *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:@"Unsupported request type" forKey:NSLocalizedDescriptionKey]];

   return nil;
}

/* ------------------------------------------------------------------ */
#pragma mark - Faulting
/* ------------------------------------------------------------------ */

/* The Z_ENT of the row with the given primary key in the given root
   table, or 0 when the row does not exist. */
-(long long)_entityIDOfRowWithPrimaryKey:(long long)primaryKey inTable:(NSString *)table {
   NSString     *sql=[NSString stringWithFormat:@"SELECT Z_ENT FROM \"%@\" WHERE Z_PK = %lld",table,primaryKey];
   sqlite3_stmt *statement=prepareStatement(DATABASE,sql,NULL);
   long long     result=0;

   if(statement==NULL)
    return 0;

   if(sqlite3_step(statement)==SQLITE_ROW)
    result=sqlite3_column_int64(statement,0);

   sqlite3_finalize(statement);

   return result;
}

/* Object ID for a foreign key pointing into the table of
   declaredDestination, resolving the row's concrete (sub)entity. */
-(NSManagedObjectID *)_objectIDForPrimaryKey:(long long)primaryKey declaredDestination:(NSEntityDescription *)declaredDestination {
   long long            entityID=[self _entityIDOfRowWithPrimaryKey:primaryKey inTable:tableNameForEntity(declaredDestination)];
   NSEntityDescription *entity=(entityID!=0)?[self _entityForEntityID:entityID]:nil;

   if(entity==nil)
    entity=declaredDestination;

   return [[self newObjectIDForEntity:entity referenceObject:referenceObjectForPrimaryKey(primaryKey)] autorelease];
}

-(NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSEntityDescription *entity=[objectID entity];
   NSDictionary        *properties=propertiesForEntityChain(entity);
   long long            primaryKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID]);
   NSMutableArray      *names=[NSMutableArray array];
   NSMutableArray      *selectColumns=[NSMutableArray arrayWithObject:@"Z_OPT"];

   for(NSString *name in [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)]){
    NSPropertyDescription *property=[properties objectForKey:name];

    if([property isKindOfClass:[NSAttributeDescription class]] ||
       ([property isKindOfClass:[NSRelationshipDescription class]] && ![(NSRelationshipDescription *)property isToMany])){
     [names addObject:name];
     [selectColumns addObject:[NSString stringWithFormat:@"\"%@\"",columnNameForProperty(name)]];
    }
   }

   NSString     *sql=[NSString stringWithFormat:@"SELECT %@ FROM \"%@\" WHERE Z_PK = %lld",[selectColumns componentsJoinedByString:@", "],tableNameForEntity(entity),primaryKey];
   sqlite3_stmt *statement=prepareStatement(DATABASE,sql,error);

   if(statement==NULL)
    return nil;

   if(sqlite3_step(statement)!=SQLITE_ROW){
    sqlite3_finalize(statement);
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSManagedObjectReferentialIntegrityError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"CoreData could not fulfill a fault for %@",objectID] forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   uint64_t             version=(uint64_t)sqlite3_column_int64(statement,0);
   NSMutableDictionary *values=[NSMutableDictionary dictionary];
   NSUInteger           i,count=[names count];

   for(i=0;i<count;i++){
    NSString              *name=[names objectAtIndex:i];
    NSPropertyDescription *property=[properties objectForKey:name];
    int                    column=(int)(i+1);

    if([property isKindOfClass:[NSAttributeDescription class]]){
     id value=attributeValueFromColumn(statement,column,(NSAttributeDescription *)property);

     if(value!=nil)
      [values setObject:value forKey:name];
    }
    else if(sqlite3_column_type(statement,column)!=SQLITE_NULL){
     long long foreignKey=sqlite3_column_int64(statement,column);

     [values setObject:[self _objectIDForPrimaryKey:foreignKey declaredDestination:[(NSRelationshipDescription *)property destinationEntity]] forKey:name];
    }
   }

   sqlite3_finalize(statement);

   return [[NSIncrementalStoreNode alloc] initWithObjectID:objectID withValues:values version:version];
}

-(id)newValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   long long            primaryKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID]);
   NSEntityDescription *destination=[relationship destinationEntity];

   if(![relationship isToMany]){
    NSString     *sql=[NSString stringWithFormat:@"SELECT \"%@\" FROM \"%@\" WHERE Z_PK = %lld",columnNameForProperty([relationship name]),tableNameForEntity([objectID entity]),primaryKey];
    sqlite3_stmt *statement=prepareStatement(DATABASE,sql,error);

    if(statement==NULL)
     return nil;

    id result=[NSNull null];

    if(sqlite3_step(statement)==SQLITE_ROW && sqlite3_column_type(statement,0)!=SQLITE_NULL)
     result=[self _objectIDForPrimaryKey:sqlite3_column_int64(statement,0) declaredDestination:destination];

    sqlite3_finalize(statement);

    return [result retain];
   }

   NSString *sql;

   if(relationshipUsesJoinTable(relationship)){
    NSDictionary *join=[self _joinSpecForRelationship:relationship];

    sql=[NSString stringWithFormat:@"SELECT \"%@\" FROM \"%@\" WHERE \"%@\" = %lld",[join objectForKey:@"destinationColumn"],[join objectForKey:@"table"],[join objectForKey:@"ownerColumn"],primaryKey];
   }
   else {
    NSRelationshipDescription *inverse=[relationship inverseRelationship];

    sql=[NSString stringWithFormat:@"SELECT Z_PK FROM \"%@\" WHERE \"%@\" = %lld ORDER BY Z_PK",tableNameForEntity(destination),columnNameForProperty([inverse name]),primaryKey];
   }

   sqlite3_stmt *statement=prepareStatement(DATABASE,sql,error);

   if(statement==NULL)
    return nil;

   NSMutableArray *result=[NSMutableArray array];

   while(sqlite3_step(statement)==SQLITE_ROW)
    [result addObject:[self _objectIDForPrimaryKey:sqlite3_column_int64(statement,0) declaredDestination:destination]];

   sqlite3_finalize(statement);

   return [[NSArray alloc] initWithArray:result];
}

/* ------------------------------------------------------------------ */
#pragma mark - Permanent IDs
/* ------------------------------------------------------------------ */

/* Reserves the next primary key for the entity by bumping Z_MAX on the
   root entity's Z_PRIMARYKEY row (subentities share the root's table and
   therefore its key space). */
-(long long)_nextPrimaryKeyForEntity:(NSEntityDescription *)entity error:(NSError **)error {
   long long rootID=[self _entityIDForEntity:rootEntity(entity)];
   NSString *sql=[NSString stringWithFormat:@"UPDATE Z_PRIMARYKEY SET Z_MAX = Z_MAX + 1 WHERE Z_ENT = %lld",rootID];

   if(!executeSQL(DATABASE,sql,error))
    return 0;

   sqlite3_stmt *statement=prepareStatement(DATABASE,[NSString stringWithFormat:@"SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_ENT = %lld",rootID],error);

   if(statement==NULL)
    return 0;

   long long result=0;

   if(sqlite3_step(statement)==SQLITE_ROW)
    result=sqlite3_column_int64(statement,0);

   sqlite3_finalize(statement);

   if(result==0 && error!=NULL)
    *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"No Z_PRIMARYKEY entry for entity %@",[entity name]] forKey:NSLocalizedDescriptionKey]];

   return result;
}

-(NSArray *)obtainPermanentIDsForObjects:(NSArray *)array error:(NSError **)error {
   NSMutableArray *result=[NSMutableArray array];

   for(NSManagedObject *object in array){
    long long primaryKey=[self _nextPrimaryKeyForEntity:[object entity] error:error];

    if(primaryKey==0)
     return nil;

    [result addObject:[[self newObjectIDForEntity:[object entity] referenceObject:referenceObjectForPrimaryKey(primaryKey)] autorelease]];
   }

   return result;
}

@end
