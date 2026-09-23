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
#import <CoreData/NSBatchInsertRequest.h>
#import <CoreData/NSBatchUpdateRequest.h>
#import <CoreData/NSBatchDeleteRequest.h>
#import "NSBatchDeleteRequest-Private.h"
#import <CoreData/NSPersistentStoreResult.h>
#import "NSPersistentStoreResult-Private.h"
#import "NSPersistentHistory-Private.h"
#import <CoreData/NSFetchRequest.h>
#import "NSFetchRequest-Private.h"
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectID.h>
#import <CoreData/NSEntityDescription.h>
#import "NSEntityDescription-Private.h"
#import <CoreData/NSAttributeDescription.h>
#import "NSAttributeDescription-Private.h"
#import "NSDerivedAttributeDescription-Private.h"
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

/* Reference objects are the plain "<Z_PK>" strings; the "p" seen in
   Apple's x-coredata://UUID/Entity/p<Z_PK> object ID URIs is added
   generically by -[NSManagedObjectID URIRepresentation] (verified on
   macOS: Apple prefixes every reference's description with "p" there).
   The parser tolerates a leading "p" for object IDs recreated from
   URIs written by older versions of this store. */
static long long primaryKeyFromReferenceObject(id referenceObject){
   NSString *string=[referenceObject description];

   if([string hasPrefix:@"p"])
    string=[string substringFromIndex:1];

   return [string longLongValue];
}

static NSString *referenceObjectForPrimaryKey(long long primaryKey){
   return [NSString stringWithFormat:@"%lld",primaryKey];
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

/* The hidden column keeping an ordered to-many's order, named with
   Apple's Z_FOK_ convention. */
static NSString *orderColumnForRelationship(NSRelationshipDescription *relationship){
   return [NSString stringWithFormat:@"Z_FOK_%@",[[relationship name] uppercaseString]];
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
    case NSURIAttributeType:
     return @"VARCHAR";
    case NSUUIDAttributeType:
     return @"BLOB";
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
     /* The value transformer (or the keyed-archiving default) produces
        the NSData blob that is stored; see NSAttributeDescription. */
     NSData *data=[attribute _dataFromTransformableValue:value];

     if(data==nil)
      sqlite3_bind_null(statement,index);
     else
      sqlite3_bind_blob(statement,index,[data bytes],(int)[data length],SQLITE_TRANSIENT);
     break;
    }
    case NSStringAttributeType:
     sqlite3_bind_text(statement,index,[[value description] UTF8String],-1,SQLITE_TRANSIENT);
     break;
    case NSUUIDAttributeType: {
     /* The 16 raw bytes, as Apple stores them. */
     uuid_t bytes;

     [(NSUUID *)value getUUIDBytes:bytes];
     sqlite3_bind_blob(statement,index,bytes,sizeof(bytes),SQLITE_TRANSIENT);
     break;
    }
    case NSURIAttributeType:
     sqlite3_bind_text(statement,index,[[(NSURL *)value absoluteString] UTF8String],-1,SQLITE_TRANSIENT);
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

     return [attribute _transformableValueFromData:data];
    }
    case NSStringAttributeType: {
     const unsigned char *text=sqlite3_column_text(statement,index);

     return (text!=NULL)?[NSString stringWithUTF8String:(const char *)text]:nil;
    }
    case NSUUIDAttributeType: {
     if(sqlite3_column_bytes(statement,index)==sizeof(uuid_t))
      return [[[NSUUID alloc] initWithUUIDBytes:sqlite3_column_blob(statement,index)] autorelease];

     const unsigned char *text=sqlite3_column_text(statement,index);

     return (text!=NULL)?[[[NSUUID alloc] initWithUUIDString:[NSString stringWithUTF8String:(const char *)text]] autorelease]:nil;
    }
    case NSURIAttributeType: {
     const unsigned char *text=sqlite3_column_text(statement,index);

     return (text!=NULL)?[NSURL URLWithString:[NSString stringWithUTF8String:(const char *)text]]:nil;
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

/* Properties of entity including the ones inherited from superentities.
   Transient properties are never persisted, so they are left out. */
static void collectPropertiesOfEntityChain(NSEntityDescription *entity,NSMutableDictionary *result){
   for(NSEntityDescription *check=entity;check!=nil;check=[check superentity])
    for(NSPropertyDescription *property in [check properties])
     if(![property isTransient] && [result objectForKey:[property name]]==nil)
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
    if(![property isTransient] && [result objectForKey:[property name]]==nil)
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

      if([property isKindOfClass:[NSAttributeDescription class]]){
       /* A derived attribute that plainly copies another attribute of
          the same table is owned by SQLite as a stored generated
          column (and is omitted from INSERT/UPDATE statements).  All
          other derivation forms - string transforms (whose SQL
          UPPER()/LOWER() are ASCII-only, unlike NSString), now() and
          aggregates - are computed by the shared engine at save time
          and stored in plain columns. */
       NSString *generatedSource=nil;

       if([property isKindOfClass:[NSDerivedAttributeDescription class]])
        generatedSource=[(NSDerivedAttributeDescription *)property _generatedColumnSourceName];

       if(generatedSource!=nil)
        [columns addObject:[NSString stringWithFormat:@"\"%@\" %@ GENERATED ALWAYS AS (\"%@\") STORED",columnNameForProperty(name),sqlTypeForAttribute((NSAttributeDescription *)property),columnNameForProperty(generatedSource)]];
       else
        [columns addObject:[NSString stringWithFormat:@"\"%@\" %@",columnNameForProperty(name),sqlTypeForAttribute((NSAttributeDescription *)property)]];
      }
      else if([property isKindOfClass:[NSRelationshipDescription class]] && ![(NSRelationshipDescription *)property isToMany])
       [columns addObject:[NSString stringWithFormat:@"\"%@\" INTEGER",columnNameForProperty(name)]];
     }

     /* An ordered foreign-key to-many keeps its order in a hidden
        Z_FOK_ column on the destination (many-side) table, as Apple
        does. */
     for(NSEntityDescription *other in sortedEntities)
      for(NSRelationshipDescription *incoming in [[other relationshipsByName] allValues])
       if([incoming isToMany] && [incoming isOrdered] &&
          !relationshipUsesJoinTable(incoming) &&
          rootEntity([incoming destinationEntity])==entity)
        [columns addObject:[NSString stringWithFormat:@"\"%@\" INTEGER",orderColumnForRelationship(incoming)]];

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

     NSMutableString *joinColumns=[NSMutableString stringWithFormat:@"\"%@\" INTEGER, \"%@\" INTEGER",[join objectForKey:@"ownerColumn"],[join objectForKey:@"destinationColumn"]];

     /* Each ordered side of a many-to-many keeps its own order
        column. */
     if([relationship isOrdered])
      [joinColumns appendFormat:@", \"%@\" INTEGER",orderColumnForRelationship(relationship)];
     if([[relationship inverseRelationship] isOrdered])
      [joinColumns appendFormat:@", \"%@\" INTEGER",orderColumnForRelationship([relationship inverseRelationship])];

     NSString *sql=[NSString stringWithFormat:@"CREATE TABLE \"%@\" (%@, PRIMARY KEY (\"%@\", \"%@\"))",table,joinColumns,[join objectForKey:@"ownerColumn"],[join objectForKey:@"destinationColumn"]];

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

   /* More than one connection can serve the same store file - a second
      coordinator in this process, or another process entirely (the
      persistent-history arrangement).  A finite busy timeout makes an
      overlapping commit wait briefly instead of failing with
      SQLITE_BUSY. */
   sqlite3_busy_timeout(DATABASE,5000);

   id trackingOption=[[self options] objectForKey:NSPersistentHistoryTrackingKey];
   id postOption=[[self options] objectForKey:NSPersistentStoreRemoteChangeNotificationPostOptionKey];

   _historyTracking=[trackingOption respondsToSelector:@selector(boolValue)] && [trackingOption boolValue];
   _postsRemoteChangeNotification=[postOption respondsToSelector:@selector(boolValue)] && [postOption boolValue];

   if(tableExists(DATABASE,@"Z_METADATA")){
    NSDictionary *metadata=readMetadata(DATABASE,error);

    if(metadata==nil)
     return NO;

    [super setMetadata:metadata];

    return [self _loadEntityIDs:error] && [self _prepareHistoryTracking:error];
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

   return [self _prepareHistoryTracking:error];
}

/* ------------------------------------------------------------------ */
#pragma mark - Persistent history
/* ------------------------------------------------------------------ */

/* Apple's history lives in ATRANSACTION/ACHANGE (plus a string-interning
   ATRANSACTIONSTRING table); this store uses the same shape under
   Z_-prefixed names, with author/context strings stored inline.  The
   transaction row's Z_PK is the transaction number, which is also what a
   history token records per store. */
-(BOOL)_prepareHistoryTracking:(NSError **)error {
   if(!_historyTracking)
    return YES;

   if(!tableExists(DATABASE,@"Z_ATRANSACTION") &&
      !executeSQL(DATABASE,@"CREATE TABLE Z_ATRANSACTION (Z_PK INTEGER PRIMARY KEY AUTOINCREMENT, ZTIMESTAMP REAL, ZAUTHOR VARCHAR, ZCONTEXTNAME VARCHAR, ZPROCESSID VARCHAR, ZBUNDLEID VARCHAR)",error))
    return NO;

   if(!tableExists(DATABASE,@"Z_ACHANGE") &&
      !executeSQL(DATABASE,@"CREATE TABLE Z_ACHANGE (Z_PK INTEGER PRIMARY KEY AUTOINCREMENT, ZTRANSACTIONID INTEGER, ZCHANGETYPE INTEGER, ZENTITY VARCHAR, ZENTITYPK INTEGER, ZUPDATEDPROPERTIES VARCHAR, ZTOMBSTONE BLOB)",error))
    return NO;

   return YES;
}

-(BOOL)_historyTrackingEnabled {
   return _historyTracking;
}

-(long long)_lastHistoryTransactionNumber {
   if(!_historyTracking || !tableExists(DATABASE,@"Z_ATRANSACTION"))
    return 0;

   sqlite3_stmt *statement=prepareStatement(DATABASE,@"SELECT MAX(Z_PK) FROM Z_ATRANSACTION",NULL);
   long long     result=0;

   if(statement==NULL)
    return 0;

   if(sqlite3_step(statement)==SQLITE_ROW)
    result=sqlite3_column_int64(statement,0);
   sqlite3_finalize(statement);

   return result;
}

/* Opens a transaction row inside the caller's BEGIN/COMMIT and answers
   its number (0 on failure). */
-(long long)_recordHistoryTransactionWithContext:(NSManagedObjectContext *)context error:(NSError **)error {
   sqlite3_stmt *statement=prepareStatement(DATABASE,@"INSERT INTO Z_ATRANSACTION (ZTIMESTAMP, ZAUTHOR, ZCONTEXTNAME, ZPROCESSID, ZBUNDLEID) VALUES (?, ?, ?, ?, ?)",error);

   if(statement==NULL)
    return 0;

   NSString *author=[context transactionAuthor];
   NSString *contextName=[context name];
   NSString *processID=[NSString stringWithFormat:@"%d",(int)[[NSProcessInfo processInfo] processIdentifier]];
   NSString *bundleID=[[NSBundle mainBundle] bundleIdentifier];

   if(bundleID==nil)
    bundleID=[[NSProcessInfo processInfo] processName];

   sqlite3_bind_double(statement,1,[[NSDate date] timeIntervalSinceReferenceDate]);
   if(author!=nil)
    sqlite3_bind_text(statement,2,[author UTF8String],-1,SQLITE_TRANSIENT);
   else
    sqlite3_bind_null(statement,2);
   if(contextName!=nil)
    sqlite3_bind_text(statement,3,[contextName UTF8String],-1,SQLITE_TRANSIENT);
   else
    sqlite3_bind_null(statement,3);
   sqlite3_bind_text(statement,4,[processID UTF8String],-1,SQLITE_TRANSIENT);
   if(bundleID!=nil)
    sqlite3_bind_text(statement,5,[bundleID UTF8String],-1,SQLITE_TRANSIENT);
   else
    sqlite3_bind_null(statement,5);

   BOOL ok=(sqlite3_step(statement)==SQLITE_DONE);

   sqlite3_finalize(statement);

   if(!ok){
    if(error!=NULL)
     *error=sqliteError(DATABASE,NSPersistentStoreSaveError,@"unable to record a history transaction");
    return 0;
   }

   return sqlite3_last_insert_rowid(DATABASE);
}

-(BOOL)_recordHistoryChangeInTransaction:(long long)transactionID
                                    type:(int)changeType
                                  entity:(NSEntityDescription *)entity
                              primaryKey:(long long)primaryKey
                       updatedProperties:(NSString *)updatedProperties
                               tombstone:(NSData *)tombstone
                                   error:(NSError **)error {
   sqlite3_stmt *statement=prepareStatement(DATABASE,@"INSERT INTO Z_ACHANGE (ZTRANSACTIONID, ZCHANGETYPE, ZENTITY, ZENTITYPK, ZUPDATEDPROPERTIES, ZTOMBSTONE) VALUES (?, ?, ?, ?, ?, ?)",error);

   if(statement==NULL)
    return NO;

   sqlite3_bind_int64(statement,1,transactionID);
   sqlite3_bind_int(statement,2,changeType);
   sqlite3_bind_text(statement,3,[[entity name] UTF8String],-1,SQLITE_TRANSIENT);
   sqlite3_bind_int64(statement,4,primaryKey);
   if(updatedProperties!=nil)
    sqlite3_bind_text(statement,5,[updatedProperties UTF8String],-1,SQLITE_TRANSIENT);
   else
    sqlite3_bind_null(statement,5);
   if(tombstone!=nil)
    sqlite3_bind_blob(statement,6,[tombstone bytes],(int)[tombstone length],SQLITE_TRANSIENT);
   else
    sqlite3_bind_null(statement,6);

   BOOL ok=(sqlite3_step(statement)==SQLITE_DONE);

   sqlite3_finalize(statement);

   if(!ok && error!=NULL)
    *error=sqliteError(DATABASE,NSPersistentStoreSaveError,@"unable to record a history change");

   return ok;
}

-(long long)_primaryKeyOfObjectID:(NSManagedObjectID *)objectID {
   return primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID]);
}

/* The tombstone for a deletion: the last values of the entity's
   attributes marked preservesValueInHistoryOnDeletion, as a binary
   plist keyed by attribute name; nil when the entity flags none. */
-(NSData *)_tombstoneForEntity:(NSEntityDescription *)entity values:(NSDictionary *)values {
   NSMutableDictionary *tombstone=nil;
   NSDictionary        *attributes=[entity attributesByName];

   for(NSString *name in attributes){
    NSAttributeDescription *attribute=[attributes objectForKey:name];

    if(![attribute preservesValueInHistoryOnDeletion])
     continue;

    id value=[values objectForKey:name];

    if(value==nil || value==[NSNull null])
     continue;
    if(tombstone==nil)
     tombstone=[NSMutableDictionary dictionary];
    [tombstone setObject:value forKey:name];
   }

   if(tombstone==nil)
    return nil;

   return [NSPropertyListSerialization dataWithPropertyList:tombstone format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}

/* Posted after a committed save or batch operation when the store was
   added with NSPersistentStoreRemoteChangeNotificationPostOptionKey.
   The signal itself is contentless, as on Apple; with history tracking
   also on, the userInfo carries the store's new token. */
-(void)_postRemoteChangeNotificationIfEnabled {
   if(!_postsRemoteChangeNotification)
    return;

   NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];

   if(_historyTracking){
    NSDictionary *positions=[NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:[self _lastHistoryTransactionNumber]] forKey:[self identifier]];
    NSPersistentHistoryToken *token=[[[NSPersistentHistoryToken alloc] _initWithPositions:positions] autorelease];

    [userInfo setObject:token forKey:NSPersistentHistoryTokenKey];
   }
   if([self URL]!=nil)
    [userInfo setObject:[self URL] forKey:@"NSPersistentStoreURL"];

   [[NSNotificationCenter defaultCenter] postNotificationName:NSPersistentStoreRemoteChangeNotification object:[self persistentStoreCoordinator] userInfo:userInfo];
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

   /* NSCountResultType: ordering cannot change a count, so sort
      descriptors are ignored; when the predicate runs in SQL the count
      comes straight from the fetched keys, without materializing
      objects. */
   BOOL countOnly=([request resultType]==NSCountResultType);

   NSString *orderBySQL=nil;
   BOOL      sortsInSQL=YES;

   if(!countOnly && [[request sortDescriptors] count]>0){
    orderBySQL=[self _translateSortDescriptors:[request sortDescriptors] entity:entity];
    sortsInSQL=(orderBySQL!=nil);
   }

   BOOL       filtersInMemory=(!predicateInSQL || !sortsInSQL);
   NSUInteger sqlLimit=filtersInMemory?0:[request fetchLimit];
   NSUInteger sqlOffset=filtersInMemory?0:[request fetchOffset];

   NSArray *objectIDs=[self _fetchObjectIDsForEntity:entity includesSubentities:[request includesSubentities] whereSQL:whereSQL bindings:bindings orderBySQL:orderBySQL fetchLimit:sqlLimit fetchOffset:sqlOffset error:error];

   if(objectIDs==nil)
    return nil;

   if(countOnly && predicateInSQL)
    return [NSArray arrayWithObject:[NSNumber numberWithUnsignedInteger:[objectIDs count]]];

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

   if(countOnly)
    return [NSArray arrayWithObject:[NSNumber numberWithUnsignedInteger:[objects count]]];

   /* Dictionary rows reflect the persisted state (committed values),
      never pending context changes, matching Apple's documented
      NSDictionaryResultType behavior.  Keys come from propertiesToFetch
      when set, otherwise every attribute. */
   if([request resultType]==NSDictionaryResultType){
    NSMutableArray *names=[NSMutableArray array];
    NSArray        *fetchProperties=[request propertiesToFetch];

    if([fetchProperties count]>0){
     for(id fetchProperty in fetchProperties)
      [names addObject:[fetchProperty isKindOfClass:[NSString class]]?fetchProperty:[(NSPropertyDescription *)fetchProperty name]];
    }
    else
     [names addObjectsFromArray:[[[entity attributesByName] allKeys] sortedArrayUsingSelector:@selector(compare:)]];

    NSMutableArray *rows=[NSMutableArray array];

    for(NSManagedObject *object in objects){
     NSDictionary        *snapshot=[object committedValuesForKeys:nil];
     NSMutableDictionary *row=[NSMutableDictionary dictionary];

     for(NSString *name in names){
      id value=[snapshot objectForKey:name];

      if(value==nil || value==[NSNull null] || [value isKindOfClass:[NSManagedObjectID class]] || [value isKindOfClass:[NSSet class]])
       continue;
      [row setObject:value forKey:name];
     }

     if([request returnsDistinctResults] && [rows containsObject:row])
      continue;
     [rows addObject:row];
    }

    return rows;
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

     /* Both sides of a many-to-many rewrite the same join rows, so
        every insert carries BOTH order columns - otherwise whichever
        side saves last would wipe the other side's order. */
     NSRelationshipDescription *inverse=[relationship inverseRelationship];
     long long                  position=0;

     for(NSManagedObject *member in members){
      long long        memberKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:[member objectID]]);
      NSMutableString *columns=[NSMutableString stringWithFormat:@"\"%@\", \"%@\"",[join objectForKey:@"ownerColumn"],[join objectForKey:@"destinationColumn"]];
      NSMutableString *values=[NSMutableString stringWithFormat:@"%lld, %lld",primaryKey,memberKey];

      if([relationship isOrdered]){
       [columns appendFormat:@", \"%@\"",orderColumnForRelationship(relationship)];
       [values appendFormat:@", %lld",position];
      }

      if([inverse isOrdered]){
       id        memberSide=[member valueForKey:[inverse name]];
       NSUInteger inversePosition=(memberSide!=nil)?[memberSide indexOfObject:object]:NSNotFound;

       [columns appendFormat:@", \"%@\"",orderColumnForRelationship(inverse)];
       if(inversePosition!=NSNotFound)
        [values appendFormat:@", %llu",(unsigned long long)inversePosition];
       else
        [values appendString:@", NULL"];
      }

      NSString *insertSQL=[NSString stringWithFormat:@"INSERT OR REPLACE INTO \"%@\" (%@) VALUES (%@)",[join objectForKey:@"table"],columns,values];

      if(!executeSQL(DATABASE,insertSQL,error))
       return NO;
      position++;
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

     long long position=0;

     for(NSManagedObject *member in members){
      long long memberKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:[member objectID]]);
      NSString *setSQL;

      if([relationship isOrdered])
       setSQL=[NSString stringWithFormat:@"UPDATE \"%@\" SET \"%@\" = %lld, \"%@\" = %lld WHERE Z_PK = %lld",destinationTable,foreignKeyColumn,primaryKey,orderColumnForRelationship(relationship),position,memberKey];
      else
       setSQL=[NSString stringWithFormat:@"UPDATE \"%@\" SET \"%@\" = %lld WHERE Z_PK = %lld",destinationTable,foreignKeyColumn,primaryKey,memberKey];

      if(!executeSQL(DATABASE,setSQL,error))
       return NO;
      position++;
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

    if([property isKindOfClass:[NSDerivedAttributeDescription class]]){
     /* Same-table generated columns are computed by SQLite and cannot be
        assigned; every other derivation is recomputed here, at save. */
     if([(NSDerivedAttributeDescription *)property _generatedColumnSourceName]!=nil)
      continue;

     value=[(NSDerivedAttributeDescription *)property _derivedValueForObject:object];
    }
    else if([property isKindOfClass:[NSAttributeDescription class]])
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

   /* To-many relationships (join rows and ordered Z_FOK columns) are
      written by _executeSaveRequest AFTER every row exists - an owner
      saved before its members would otherwise UPDATE rows that are not
      there yet. */
   return YES;
}

-(BOOL)_deleteRowForObject:(NSManagedObject *)object error:(NSError **)error {
   return [self _deleteRowWithEntity:[object entity]
                          primaryKey:primaryKeyFromReferenceObject([self referenceObjectForObjectID:[object objectID]])
                               error:error];
}

-(BOOL)_deleteRowWithEntity:(NSEntityDescription *)entity primaryKey:(long long)primaryKey error:(NSError **)error {
   NSDictionary *properties=propertiesForEntityChain(entity);

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

   /* Every row exists now; write join rows and ordered positions. */
   for(NSManagedObject *object in [request insertedObjects]){
    if(![self _writeToManyRelationshipsForObject:object error:error]){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }
   }

   for(NSManagedObject *object in [request updatedObjects]){
    if(![self _writeToManyRelationshipsForObject:object error:error]){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }
   }

   /* Tombstones read committed values, so capture them before the rows
      are deleted (they are, in fact, read from the objects, but keep
      the ordering conservative). */
   NSUInteger changeCount=[[request insertedObjects] count]+[[request updatedObjects] count]+[[request deletedObjects] count];

   if(_historyTracking && changeCount>0){
    long long transactionID=[self _recordHistoryTransactionWithContext:context error:error];

    if(transactionID==0){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }

    for(NSManagedObject *object in [request insertedObjects]){
     if(![self _recordHistoryChangeInTransaction:transactionID type:NSPersistentHistoryChangeTypeInsert entity:[object entity] primaryKey:[self _primaryKeyOfObjectID:[object objectID]] updatedProperties:nil tombstone:nil error:error]){
      executeSQL(DATABASE,@"ROLLBACK",NULL);
      return nil;
     }
    }

    for(NSManagedObject *object in [request updatedObjects]){
     NSArray  *changedKeys=[[[object changedValues] allKeys] sortedArrayUsingSelector:@selector(compare:)];
     NSString *updatedProperties=([changedKeys count]>0)?[changedKeys componentsJoinedByString:@","]:nil;

     if(![self _recordHistoryChangeInTransaction:transactionID type:NSPersistentHistoryChangeTypeUpdate entity:[object entity] primaryKey:[self _primaryKeyOfObjectID:[object objectID]] updatedProperties:updatedProperties tombstone:nil error:error]){
      executeSQL(DATABASE,@"ROLLBACK",NULL);
      return nil;
     }
    }

    for(NSManagedObject *object in [request deletedObjects]){
     NSData *tombstone=[self _tombstoneForEntity:[object entity] values:[object committedValuesForKeys:nil]];

     if(![self _recordHistoryChangeInTransaction:transactionID type:NSPersistentHistoryChangeTypeDelete entity:[object entity] primaryKey:[self _primaryKeyOfObjectID:[object objectID]] updatedProperties:nil tombstone:tombstone error:error]){
      executeSQL(DATABASE,@"ROLLBACK",NULL);
      return nil;
     }
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

   if(changeCount>0)
    [self _postRemoteChangeNotificationIfEnabled];

   return [NSArray array];
}

/* ------------------------------------------------------------------ */
#pragma mark - Batch requests
/* ------------------------------------------------------------------ */

/* Batch requests execute directly against the database: no
   NSManagedObjects are materialized, no validation or delete rules
   run (beyond the store's own join-table/foreign-key cleanup), and
   loaded contexts are not notified. */

-(NSEntityDescription *)_batchEntityForName:(NSString *)name entity:(NSEntityDescription *)entity error:(NSError **)error {
   if(entity!=nil)
    return entity;

   NSEntityDescription *named=[[[[self persistentStoreCoordinator] managedObjectModel] entitiesByName] objectForKey:name];

   if(named==nil && error!=NULL)
    *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"batch request: no entity named '%@' in this model",name] forKey:NSLocalizedDescriptionKey]];

   return named;
}

/* The object IDs a batch update/delete targets.  The predicate is
   pushed into SQL when it translates exactly; otherwise it is
   evaluated in memory against each row's attribute snapshot. */
-(NSArray *)_batchTargetObjectIDsForEntity:(NSEntityDescription *)entity predicate:(NSPredicate *)predicate includesSubentities:(BOOL)includesSubentities error:(NSError **)error {
   NSMutableArray *bindings=[NSMutableArray array];
   NSString       *whereSQL=nil;
   BOOL            predicateInSQL=YES;

   if(predicate!=nil){
    whereSQL=[self _translatePredicate:predicate entity:entity bindings:bindings];
    predicateInSQL=(whereSQL!=nil);

    if(!predicateInSQL)
     [bindings removeAllObjects];
   }

   NSArray *objectIDs=[self _fetchObjectIDsForEntity:entity includesSubentities:includesSubentities whereSQL:whereSQL bindings:bindings orderBySQL:nil fetchLimit:0 fetchOffset:0 error:error];

   if(objectIDs==nil || predicateInSQL)
    return objectIDs;

   NSMutableArray *result=[NSMutableArray array];

   for(NSManagedObjectID *objectID in objectIDs){
    NSIncrementalStoreNode *node=[self newValuesForObjectWithID:objectID withContext:nil error:error];

    if(node==nil)
     return nil;

    NSMutableDictionary *row=[NSMutableDictionary dictionary];
    NSDictionary        *attributes=[[objectID entity] attributesByName];

    for(NSString *name in attributes){
     id value=[node valueForPropertyDescription:[attributes objectForKey:name]];

     if(value!=nil && value!=[NSNull null])
      [row setObject:value forKey:name];
    }
    [node release];

    BOOL matches=NO;

    NS_DURING
     matches=[predicate evaluateWithObject:row];
    NS_HANDLER
     matches=NO;
    NS_ENDHANDLER

    if(matches)
     [result addObject:objectID];
   }

   return result;
}

-(id)_executeBatchInsertRequest:(NSBatchInsertRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSEntityDescription *entity=[self _batchEntityForName:[request entityName] entity:[request entity] error:error];

   if(entity==nil)
    return nil;

   NSMutableArray *rows=[NSMutableArray array];

   if([request dictionaryHandler]!=NULL){
    BOOL (^handler)(NSMutableDictionary *)=[request dictionaryHandler];

    for(;;){
     NSMutableDictionary *row=[NSMutableDictionary dictionary];

     /* YES means "done"; the dictionary from that final call is not
        inserted. */
     if(handler(row))
      break;

     [rows addObject:row];
    }
   }
   else if([request objectsToInsert]!=nil)
    [rows addObjectsFromArray:[request objectsToInsert]];

   NSDictionary *properties=propertiesForEntityChain(entity);

   if(!executeSQL(DATABASE,@"BEGIN",error))
    return nil;

   NSMutableArray *insertedIDs=[NSMutableArray array];

   for(NSDictionary *row in rows){
    long long primaryKey=[self _nextPrimaryKeyForEntity:entity error:error];

    if(primaryKey==0){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }

    NSMutableArray *columns=[NSMutableArray arrayWithObjects:@"Z_PK",@"Z_ENT",@"Z_OPT",nil];
    NSMutableArray *placeholders=[NSMutableArray arrayWithObjects:@"?",@"?",@"?",nil];
    NSMutableArray *boundAttributes=[NSMutableArray array];
    NSMutableArray *boundValues=[NSMutableArray array];

    for(NSString *name in [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)]){
     NSPropertyDescription *property=[properties objectForKey:name];

     if(![property isKindOfClass:[NSAttributeDescription class]])
      continue;   /* relationships cannot be batch inserted */
     if([property isKindOfClass:[NSDerivedAttributeDescription class]] && [(NSDerivedAttributeDescription *)property _generatedColumnSourceName]!=nil)
      continue;   /* computed by SQLite */

     id value=[row objectForKey:name];

     if(value==nil)
      value=[(NSAttributeDescription *)property defaultValue];
     if(value==nil)
      continue;

     [columns addObject:[NSString stringWithFormat:@"\"%@\"",columnNameForProperty(name)]];
     [placeholders addObject:@"?"];
     [boundAttributes addObject:property];
     [boundValues addObject:value];
    }

    NSString     *sql=[NSString stringWithFormat:@"INSERT INTO \"%@\" (%@) VALUES (%@)",tableNameForEntity(entity),[columns componentsJoinedByString:@", "],[placeholders componentsJoinedByString:@", "]];
    sqlite3_stmt *statement=prepareStatement(DATABASE,sql,error);

    if(statement==NULL){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }

    int index=1;

    sqlite3_bind_int64(statement,index++,primaryKey);
    sqlite3_bind_int64(statement,index++,[self _entityIDForEntity:entity]);
    sqlite3_bind_int64(statement,index++,1);

    NSUInteger i,count=[boundAttributes count];

    for(i=0;i<count;i++){
     id value=[boundValues objectAtIndex:i];

     if(value==[NSNull null])
      sqlite3_bind_null(statement,index++);
     else
      bindAttributeValue(statement,index++,[boundAttributes objectAtIndex:i],value);
    }

    BOOL ok=(sqlite3_step(statement)==SQLITE_DONE);

    sqlite3_finalize(statement);

    if(!ok){
     if(error!=NULL)
      *error=sqliteError(DATABASE,NSPersistentStoreSaveError,[NSString stringWithFormat:@"unable to batch insert into %@",[entity name]]);
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }

    [insertedIDs addObject:[[self newObjectIDForEntity:entity referenceObject:referenceObjectForPrimaryKey(primaryKey)] autorelease]];
   }

   if(_historyTracking && [insertedIDs count]>0){
    long long transactionID=[self _recordHistoryTransactionWithContext:context error:error];

    if(transactionID==0){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }

    for(NSManagedObjectID *objectID in insertedIDs){
     if(![self _recordHistoryChangeInTransaction:transactionID type:NSPersistentHistoryChangeTypeInsert entity:entity primaryKey:[self _primaryKeyOfObjectID:objectID] updatedProperties:nil tombstone:nil error:error]){
      executeSQL(DATABASE,@"ROLLBACK",NULL);
      return nil;
     }
    }
   }

   if(!writeMetadata(DATABASE,[self metadata],error) || !executeSQL(DATABASE,@"COMMIT",error)){
    executeSQL(DATABASE,@"ROLLBACK",NULL);
    return nil;
   }

   if([insertedIDs count]>0)
    [self _postRemoteChangeNotificationIfEnabled];

   switch([request resultType]){
    case NSBatchInsertRequestResultTypeObjectIDs:
     return [[[NSBatchInsertResult alloc] _initWithResult:insertedIDs resultType:NSBatchInsertRequestResultTypeObjectIDs] autorelease];
    case NSBatchInsertRequestResultTypeCount:
     return [[[NSBatchInsertResult alloc] _initWithResult:[NSNumber numberWithUnsignedInteger:[insertedIDs count]] resultType:NSBatchInsertRequestResultTypeCount] autorelease];
    default:
     return [[[NSBatchInsertResult alloc] _initWithResult:[NSNumber numberWithBool:YES] resultType:NSBatchInsertRequestResultTypeStatusOnly] autorelease];
   }
}

-(id)_executeBatchUpdateRequest:(NSBatchUpdateRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSEntityDescription *entity=[self _batchEntityForName:[request entityName] entity:[request entity] error:error];

   if(entity==nil)
    return nil;

   NSArray *targetIDs=[self _batchTargetObjectIDsForEntity:entity predicate:[request predicate] includesSubentities:[request includesSubentities] error:error];

   if(targetIDs==nil)
    return nil;

   NSDictionary   *properties=propertiesForEntityChain(entity);
   NSMutableArray *assignments=[NSMutableArray arrayWithObject:@"Z_OPT = Z_OPT + 1"];
   NSMutableArray *boundAttributes=[NSMutableArray array];
   NSMutableArray *boundValues=[NSMutableArray array];
   NSDictionary   *updates=[request propertiesToUpdate];

   for(id key in updates){
    NSString              *name=[key isKindOfClass:[NSPropertyDescription class]]?[(NSPropertyDescription *)key name]:(NSString *)key;
    NSPropertyDescription *property=[properties objectForKey:name];

    if(![property isKindOfClass:[NSAttributeDescription class]]){
     if(error!=NULL)
      *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"batch update: '%@' is not an attribute of %@",name,[entity name]] forKey:NSLocalizedDescriptionKey]];
     return nil;
    }

    id value=[updates objectForKey:key];

    if([value isKindOfClass:[NSExpression class]])
     value=[(NSExpression *)value expressionValueWithObject:nil context:nil];

    [assignments addObject:[NSString stringWithFormat:@"\"%@\" = ?",columnNameForProperty(name)]];
    [boundAttributes addObject:property];
    [boundValues addObject:(value!=nil)?value:(id)[NSNull null]];
   }

   if(!executeSQL(DATABASE,@"BEGIN",error))
    return nil;

   NSUInteger chunkStart,total=[targetIDs count];

   for(chunkStart=0;chunkStart<total;chunkStart+=500){
    NSRange         range=NSMakeRange(chunkStart,MIN((NSUInteger)500,total-chunkStart));
    NSMutableArray *pks=[NSMutableArray array];

    for(NSManagedObjectID *objectID in [targetIDs subarrayWithRange:range])
     [pks addObject:[NSString stringWithFormat:@"%lld",primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID])]];

    NSString     *sql=[NSString stringWithFormat:@"UPDATE \"%@\" SET %@ WHERE Z_PK IN (%@)",tableNameForEntity(entity),[assignments componentsJoinedByString:@", "],[pks componentsJoinedByString:@", "]];
    sqlite3_stmt *statement=prepareStatement(DATABASE,sql,error);

    if(statement==NULL){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }

    int        index=1;
    NSUInteger i,count=[boundAttributes count];

    for(i=0;i<count;i++){
     id value=[boundValues objectAtIndex:i];

     if(value==[NSNull null])
      sqlite3_bind_null(statement,index++);
     else
      bindAttributeValue(statement,index++,[boundAttributes objectAtIndex:i],value);
    }

    BOOL ok=(sqlite3_step(statement)==SQLITE_DONE);

    sqlite3_finalize(statement);

    if(!ok){
     if(error!=NULL)
      *error=sqliteError(DATABASE,NSPersistentStoreSaveError,[NSString stringWithFormat:@"unable to batch update %@",[entity name]]);
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }
   }

   if(_historyTracking && total>0){
    NSMutableArray *names=[NSMutableArray array];

    for(id key in updates)
     [names addObject:[key isKindOfClass:[NSPropertyDescription class]]?[(NSPropertyDescription *)key name]:(NSString *)key];
    [names sortUsingSelector:@selector(compare:)];

    NSString *updatedProperties=([names count]>0)?[names componentsJoinedByString:@","]:nil;
    long long transactionID=[self _recordHistoryTransactionWithContext:context error:error];

    if(transactionID==0){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }

    for(NSManagedObjectID *objectID in targetIDs){
     if(![self _recordHistoryChangeInTransaction:transactionID type:NSPersistentHistoryChangeTypeUpdate entity:[objectID entity] primaryKey:[self _primaryKeyOfObjectID:objectID] updatedProperties:updatedProperties tombstone:nil error:error]){
      executeSQL(DATABASE,@"ROLLBACK",NULL);
      return nil;
     }
    }
   }

   if(!writeMetadata(DATABASE,[self metadata],error) || !executeSQL(DATABASE,@"COMMIT",error)){
    executeSQL(DATABASE,@"ROLLBACK",NULL);
    return nil;
   }

   if(total>0)
    [self _postRemoteChangeNotificationIfEnabled];

   switch([request resultType]){
    case NSUpdatedObjectIDsResultType:
     return [[[NSBatchUpdateResult alloc] _initWithResult:targetIDs resultType:NSUpdatedObjectIDsResultType] autorelease];
    case NSUpdatedObjectsCountResultType:
     return [[[NSBatchUpdateResult alloc] _initWithResult:[NSNumber numberWithUnsignedInteger:total] resultType:NSUpdatedObjectsCountResultType] autorelease];
    default:
     return [[[NSBatchUpdateResult alloc] _initWithResult:[NSNumber numberWithBool:YES] resultType:NSStatusOnlyResultType] autorelease];
   }
}

-(id)_executeBatchDeleteRequest:(NSBatchDeleteRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSArray *explicitIDs=[request _objectIDsToDelete];
   NSArray *targetIDs=nil;

   if(explicitIDs!=nil){
    /* Keep only IDs whose rows actually exist in this store. */
    NSMutableArray *existing=[NSMutableArray array];

    for(NSManagedObjectID *objectID in explicitIDs){
     if([objectID isTemporaryID])
      continue;

     long long primaryKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID]);

     if([self _entityIDOfRowWithPrimaryKey:primaryKey inTable:tableNameForEntity([objectID entity])]!=0)
      [existing addObject:objectID];
    }

    targetIDs=existing;
   }
   else {
    NSFetchRequest      *fetch=[request fetchRequest];
    NSEntityDescription *entity=[fetch _entityIfResolved];

    if(entity==nil){
     if(error!=NULL)
      *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:@"batch delete: the fetch request has no entity" forKey:NSLocalizedDescriptionKey]];
     return nil;
    }

    targetIDs=[self _batchTargetObjectIDsForEntity:entity predicate:[fetch predicate] includesSubentities:[fetch includesSubentities] error:error];

    if(targetIDs==nil)
     return nil;
   }

   if(!executeSQL(DATABASE,@"BEGIN",error))
    return nil;

   /* History records first: a deletion's tombstone reads the row's
      current values, which are gone once the row is. */
   if(_historyTracking && [targetIDs count]>0){
    long long transactionID=[self _recordHistoryTransactionWithContext:context error:error];

    if(transactionID==0){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }

    for(NSManagedObjectID *objectID in targetIDs){
     NSEntityDescription *entity=[objectID entity];
     NSData              *tombstone=nil;
     BOOL                 wantsTombstone=NO;

     for(NSAttributeDescription *attribute in [[entity attributesByName] allValues])
      if([attribute preservesValueInHistoryOnDeletion]){
       wantsTombstone=YES;
       break;
      }

     if(wantsTombstone){
      NSIncrementalStoreNode *node=[self newValuesForObjectWithID:objectID withContext:nil error:NULL];

      if(node!=nil){
       NSMutableDictionary *values=[NSMutableDictionary dictionary];
       NSDictionary        *attributes=[entity attributesByName];

       for(NSString *name in attributes){
        id value=[node valueForPropertyDescription:[attributes objectForKey:name]];

        if(value!=nil && value!=[NSNull null])
         [values setObject:value forKey:name];
       }
       [node release];

       tombstone=[self _tombstoneForEntity:entity values:values];
      }
     }

     if(![self _recordHistoryChangeInTransaction:transactionID type:NSPersistentHistoryChangeTypeDelete entity:entity primaryKey:[self _primaryKeyOfObjectID:objectID] updatedProperties:nil tombstone:tombstone error:error]){
      executeSQL(DATABASE,@"ROLLBACK",NULL);
      return nil;
     }
    }
   }

   for(NSManagedObjectID *objectID in targetIDs){
    if(![self _deleteRowWithEntity:[objectID entity] primaryKey:primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID]) error:error]){
     executeSQL(DATABASE,@"ROLLBACK",NULL);
     return nil;
    }
   }

   if(!writeMetadata(DATABASE,[self metadata],error) || !executeSQL(DATABASE,@"COMMIT",error)){
    executeSQL(DATABASE,@"ROLLBACK",NULL);
    return nil;
   }

   if([targetIDs count]>0)
    [self _postRemoteChangeNotificationIfEnabled];

   switch([request resultType]){
    case NSBatchDeleteResultTypeObjectIDs:
     return [[[NSBatchDeleteResult alloc] _initWithResult:targetIDs resultType:NSBatchDeleteResultTypeObjectIDs] autorelease];
    case NSBatchDeleteResultTypeCount:
     return [[[NSBatchDeleteResult alloc] _initWithResult:[NSNumber numberWithUnsignedInteger:[targetIDs count]] resultType:NSBatchDeleteResultTypeCount] autorelease];
    default:
     return [[[NSBatchDeleteResult alloc] _initWithResult:[NSNumber numberWithBool:YES] resultType:NSBatchDeleteResultTypeStatusOnly] autorelease];
   }
}

/* ------------------------------------------------------------------ */
#pragma mark - History requests
/* ------------------------------------------------------------------ */

/* Both anchor directions are exclusive (verified on macOS): a fetch
   "after" an anchor returns strictly newer transactions, and a purge
   "before" an anchor removes strictly older ones - the anchor's own
   transaction survives the purge, even though an "after" fetch does
   not return it either. */
-(id)_executeHistoryRequest:(NSPersistentHistoryChangeRequest *)request error:(NSError **)error {
   if(!_historyTracking){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:@"Persistent history tracking is not enabled on this store (NSPersistentHistoryTrackingKey)." forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   /* Resolve the anchor to either a transaction number or a timestamp. */
   long long anchorNumber=0;
   NSDate   *anchorDate=[request _anchorDate];
   BOOL      byDate=(anchorDate!=nil);

   if(!byDate){
    if([request _anchorTransactionNumber]>=0)
     anchorNumber=[request _anchorTransactionNumber];
    else if([request _anchorToken]!=nil)
     anchorNumber=[[request _anchorToken] _transactionNumberForStoreIdentifier:[self identifier]];
   }

   if([request _isPurge]){
    NSString *transactionCondition=byDate?
        [NSString stringWithFormat:@"ZTIMESTAMP < %f",[anchorDate timeIntervalSinceReferenceDate]]:
        [NSString stringWithFormat:@"Z_PK < %lld",anchorNumber];

    if(!executeSQL(DATABASE,[NSString stringWithFormat:@"DELETE FROM Z_ACHANGE WHERE ZTRANSACTIONID IN (SELECT Z_PK FROM Z_ATRANSACTION WHERE %@)",transactionCondition],error))
     return nil;
    if(!executeSQL(DATABASE,[NSString stringWithFormat:@"DELETE FROM Z_ATRANSACTION WHERE %@",transactionCondition],error))
     return nil;

    return [[[NSPersistentHistoryResult alloc] _initWithResult:[NSNumber numberWithBool:YES] resultType:NSPersistentHistoryResultTypeStatusOnly] autorelease];
   }

   /* The predicate-filtered flavor: the attached fetch request names
      one of the two synthetic history entities, and its predicate is
      evaluated in memory against the materialized transaction/change
      objects (their accessors are the entity's property names, so KVC
      resolves the key paths exactly).  History stays small when
      applications purge, so nothing here is worth pushing into SQL. */
   NSFetchRequest      *filter=[request fetchRequest];
   BOOL                 filtersTransactions=NO,filtersChanges=NO;

   if(filter!=nil){
    NSEntityDescription *filterEntity=[filter _entityIfResolved];

    if(filterEntity==[NSPersistentHistoryTransaction entityDescription])
     filtersTransactions=YES;
    else if(filterEntity==[NSPersistentHistoryChange entityDescription])
     filtersChanges=YES;
    else {
     if(error!=NULL)
      *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:@"fetchHistoryWithFetchRequest: requires a fetch request built on +[NSPersistentHistoryTransaction entityDescription] or +[NSPersistentHistoryChange entityDescription]." forKey:NSLocalizedDescriptionKey]];
     return nil;
    }

    /* Arbitrated on macOS: sort descriptors on a history fetch raise
       there for every public keypath (Apple resolves them against its
       internal TRANSACTION entity, whose attribute names differ from
       the public accessors - transactionNumber and timestamp both
       throw "keypath not found").  Raise the same way, so code cannot
       come to rely on an ordering Apple refuses to provide; results
       come back in transaction order. */
    if([[filter sortDescriptors] count]>0)
     [NSException raise:NSInvalidArgumentException
                 format:@"keypath %@ not found in entity TRANSACTION (history fetch requests do not support sort descriptors, matching Apple CoreData)",[[[filter sortDescriptors] objectAtIndex:0] key]];
   }

   NSPersistentHistoryResultType resultType=[request resultType];
   NSString *transactionCondition=byDate?
       [NSString stringWithFormat:@"ZTIMESTAMP > %f",[anchorDate timeIntervalSinceReferenceDate]]:
       [NSString stringWithFormat:@"Z_PK > %lld",anchorNumber];
   sqlite3_stmt *statement=prepareStatement(DATABASE,[NSString stringWithFormat:@"SELECT Z_PK, ZTIMESTAMP, ZAUTHOR, ZCONTEXTNAME, ZPROCESSID, ZBUNDLEID FROM Z_ATRANSACTION WHERE %@ ORDER BY Z_PK",transactionCondition],error);

   if(statement==NULL)
    return nil;

   NSMutableArray *transactions=[NSMutableArray array];

   while(sqlite3_step(statement)==SQLITE_ROW){
    long long            number=sqlite3_column_int64(statement,0);
    NSDate              *timestamp=[NSDate dateWithTimeIntervalSinceReferenceDate:sqlite3_column_double(statement,1)];
    const unsigned char *author=sqlite3_column_text(statement,2);
    const unsigned char *contextName=sqlite3_column_text(statement,3);
    const unsigned char *processID=sqlite3_column_text(statement,4);
    const unsigned char *bundleID=sqlite3_column_text(statement,5);
    NSPersistentHistoryTransaction *transaction=[[[NSPersistentHistoryTransaction alloc]
        _initWithNumber:number
              timestamp:timestamp
                 author:(author!=NULL)?[NSString stringWithUTF8String:(const char *)author]:nil
            contextName:(contextName!=NULL)?[NSString stringWithUTF8String:(const char *)contextName]:nil
              processID:(processID!=NULL)?[NSString stringWithUTF8String:(const char *)processID]:nil
               bundleID:(bundleID!=NULL)?[NSString stringWithUTF8String:(const char *)bundleID]:nil
                storeID:[self identifier]
                changes:nil] autorelease];

    [transactions addObject:transaction];
   }
   sqlite3_finalize(statement);

   /* A transaction-entity predicate keeps whole transactions. */
   if(filtersTransactions && [filter predicate]!=nil)
    transactions=[[[transactions filteredArrayUsingPredicate:[filter predicate]] mutableCopy] autorelease];

   /* Changes are needed for the changes-shaped results - and to
      evaluate a change-entity predicate whatever the result type,
      since a transaction whose changes all fail it is dropped. */
   BOOL wantsChanges=filtersChanges ||
       (resultType==NSPersistentHistoryResultTypeTransactionsAndChanges ||
        resultType==NSPersistentHistoryResultTypeChangesOnly ||
        resultType==NSPersistentHistoryResultTypeObjectIDs);

   NSDictionary   *entitiesByName=[[[self persistentStoreCoordinator] managedObjectModel] entitiesByName];
   NSMutableArray *keptTransactions=wantsChanges?[NSMutableArray array]:(NSMutableArray *)transactions;
   NSMutableArray *allChanges=[NSMutableArray array];
   NSMutableArray *allObjectIDs=[NSMutableArray array];

   if(wantsChanges)
   for(NSPersistentHistoryTransaction *transaction in transactions){
    sqlite3_stmt *changeStatement=prepareStatement(DATABASE,@"SELECT Z_PK, ZCHANGETYPE, ZENTITY, ZENTITYPK, ZUPDATEDPROPERTIES, ZTOMBSTONE FROM Z_ACHANGE WHERE ZTRANSACTIONID = ? ORDER BY Z_PK",error);

    if(changeStatement==NULL)
     return nil;

    sqlite3_bind_int64(changeStatement,1,[transaction transactionNumber]);

    NSMutableArray *changes=[NSMutableArray array];

    while(sqlite3_step(changeStatement)==SQLITE_ROW){
     long long            changeID=sqlite3_column_int64(changeStatement,0);
     int                  changeType=sqlite3_column_int(changeStatement,1);
     const unsigned char *entityName=sqlite3_column_text(changeStatement,2);
     long long            primaryKey=sqlite3_column_int64(changeStatement,3);
     const unsigned char *updatedNames=sqlite3_column_text(changeStatement,4);
     NSEntityDescription *entity=(entityName!=NULL)?[entitiesByName objectForKey:[NSString stringWithUTF8String:(const char *)entityName]]:nil;

     if(entity==nil)
      continue;   /* recorded against an entity the current model lacks */

     NSManagedObjectID *objectID=[[self newObjectIDForEntity:entity referenceObject:referenceObjectForPrimaryKey(primaryKey)] autorelease];
     NSMutableSet      *updatedProperties=nil;

     if(updatedNames!=NULL){
      NSDictionary *propertiesByName=[entity propertiesByName];

      updatedProperties=[NSMutableSet set];
      for(NSString *name in [[NSString stringWithUTF8String:(const char *)updatedNames] componentsSeparatedByString:@","]){
       NSPropertyDescription *property=[propertiesByName objectForKey:name];

       if(property!=nil)
        [updatedProperties addObject:property];
      }
     }

     NSDictionary *tombstone=nil;

     if(sqlite3_column_type(changeStatement,5)==SQLITE_BLOB){
      const void *bytes=sqlite3_column_blob(changeStatement,5);
      int         length=sqlite3_column_bytes(changeStatement,5);

      if(bytes!=NULL && length>0){
       NSData *data=[NSData dataWithBytes:bytes length:length];

       tombstone=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
      }
     }

     NSPersistentHistoryChange *change=[[[NSPersistentHistoryChange alloc] _initWithChangeID:changeID type:changeType objectID:objectID updatedProperties:updatedProperties tombstone:tombstone] autorelease];

     /* A change-entity predicate keeps individual changes. */
     if(filtersChanges && [filter predicate]!=nil &&
        ![[filter predicate] evaluateWithObject:change])
      continue;

     [changes addObject:change];
     [allObjectIDs addObject:objectID];
    }
    sqlite3_finalize(changeStatement);

    /* A change-filtered transaction with nothing left is dropped. */
    if(filtersChanges && [changes count]==0)
     continue;

    /* Only a transactions-shaped result ties changes to their
       transaction: the back-pointer is unretained, so a flat changes
       result (which does not keep the transactions alive) leaves it
       nil.  A Change-entity fetch request always answers flat changes,
       whatever the result type. */
    if(resultType==NSPersistentHistoryResultTypeTransactionsAndChanges && !filtersChanges)
     [transaction _setChanges:changes];
    [allChanges addObjectsFromArray:changes];
    [keptTransactions addObject:transaction];
   }

   /* A Change-entity fetch request answers the matching changes
      themselves, not transactions (arbitrated on macOS, where the
      result held _NSPersistentHistoryChange objects). */
   BOOL flatChanges=filtersChanges || (resultType==NSPersistentHistoryResultTypeChangesOnly);

   /* The fetch request's limit/offset apply to the result's top-level
      collection: the flat changes for a changes-shaped result, the
      transactions otherwise.  (Sort descriptors were rejected above.) */
   if(filter!=nil){
    NSMutableArray *topLevel=flatChanges?allChanges:keptTransactions;

    NSUInteger offset=[filter fetchOffset];
    NSUInteger limit=[filter fetchLimit];

    if(offset>0 || limit>0){
     if(offset>[topLevel count])
      offset=[topLevel count];

     NSUInteger length=[topLevel count]-offset;

     if(limit>0 && limit<length)
      length=limit;
     topLevel=[[[topLevel subarrayWithRange:NSMakeRange(offset,length)] mutableCopy] autorelease];
    }

    if(flatChanges)
     allChanges=topLevel;
    else
     keptTransactions=topLevel;
   }

   switch(resultType){
    case NSPersistentHistoryResultTypeStatusOnly:
     return [[[NSPersistentHistoryResult alloc] _initWithResult:[NSNumber numberWithBool:YES] resultType:resultType] autorelease];
    case NSPersistentHistoryResultTypeCount:
     return [[[NSPersistentHistoryResult alloc] _initWithResult:[NSNumber numberWithUnsignedInteger:flatChanges?[allChanges count]:[keptTransactions count]] resultType:resultType] autorelease];
    case NSPersistentHistoryResultTypeObjectIDs:
     return [[[NSPersistentHistoryResult alloc] _initWithResult:allObjectIDs resultType:resultType] autorelease];
    case NSPersistentHistoryResultTypeChangesOnly:
     return [[[NSPersistentHistoryResult alloc] _initWithResult:allChanges resultType:resultType] autorelease];
    case NSPersistentHistoryResultTypeTransactionsOnly:
     return [[[NSPersistentHistoryResult alloc] _initWithResult:keptTransactions resultType:resultType] autorelease];
    default:
     return [[[NSPersistentHistoryResult alloc] _initWithResult:flatChanges?allChanges:keptTransactions resultType:NSPersistentHistoryResultTypeTransactionsAndChanges] autorelease];
   }
}

-(id)executeRequest:(NSPersistentStoreRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   if([request requestType]==NSFetchRequestType)
    return [self _executeFetchRequest:(NSFetchRequest *)request withContext:context error:error];

   if([request requestType]==NSSaveRequestType)
    return [self _executeSaveRequest:(NSSaveChangesRequest *)request withContext:context error:error];

   if([request requestType]==NSBatchInsertRequestType)
    return [self _executeBatchInsertRequest:(NSBatchInsertRequest *)request withContext:context error:error];

   if([request requestType]==NSBatchUpdateRequestType)
    return [self _executeBatchUpdateRequest:(NSBatchUpdateRequest *)request withContext:context error:error];

   if([request requestType]==NSBatchDeleteRequestType)
    return [self _executeBatchDeleteRequest:(NSBatchDeleteRequest *)request withContext:context error:error];

   if([request requestType]==NSPersistentHistoryRequestType)
    return [self _executeHistoryRequest:(NSPersistentHistoryChangeRequest *)request error:error];

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
    NSString     *orderBy=[relationship isOrdered]
        ?[NSString stringWithFormat:@" ORDER BY \"%@\"",orderColumnForRelationship(relationship)]
        :@"";

    sql=[NSString stringWithFormat:@"SELECT \"%@\" FROM \"%@\" WHERE \"%@\" = %lld%@",[join objectForKey:@"destinationColumn"],[join objectForKey:@"table"],[join objectForKey:@"ownerColumn"],primaryKey,orderBy];
   }
   else {
    NSRelationshipDescription *inverse=[relationship inverseRelationship];
    NSString                  *orderBy=[relationship isOrdered]
        ?[NSString stringWithFormat:@"\"%@\"",orderColumnForRelationship(relationship)]
        :@"Z_PK";

    sql=[NSString stringWithFormat:@"SELECT Z_PK FROM \"%@\" WHERE \"%@\" = %lld ORDER BY %@",tableNameForEntity(destination),columnNameForProperty([inverse name]),primaryKey,orderBy];
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
