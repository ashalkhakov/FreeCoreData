/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

/* The structure of this store deliberately follows
   CoreData/NSSQLitePersistentStore.m: same schema, same naming, same
   decisions about what is pushed into SQL and what is evaluated in memory.
   Where the two differ, PostgreSQL's way is commented.

   This file uses the framework's PUBLIC headers only (see ../README.md), so
   it also compiles against Apple's CoreData on macOS. */

#import "CDSQLStore.h"
#import "CDSQLQuery.h"

static long long advisoryLockKeyForSchema(NSString *schema);

NSString * const CDSQLStoreSchemaNameOption=@"CDSQLStoreSchemaName";
NSString * const CDSQLStoreMigrateSchemaOption=@"CDSQLStoreMigrateSchema";


/* The value of Z_VERSION written by (and accepted from) this store. */
enum { CDSQLStoreMetadataVersion=1 };

/* PostgreSQL's parameter limit is 65535, far above anything a sensible IN
   list holds; the cap is here so that a pathological collection is evaluated
   in memory instead of building an enormous statement. */
enum { CDSQLStoreMaxInListSize=900 };

/* ------------------------------------------------------------------ */
#pragma mark - Naming helpers (the SQLite store's schema names)
/* ------------------------------------------------------------------ */

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

/* Every identifier this store emits is quoted, so the upper-case names
   survive PostgreSQL's habit of folding unquoted identifiers to lower case.
   A quote inside the name is doubled, as SQL requires: these names come from
   the model rather than from user input, but a model is free to contain one
   and the alternative is emitting broken SQL. */
static NSString *quoted(NSString *identifier){
   return [NSString stringWithFormat:@"\"%@\"",[identifier stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

/* The hidden column keeping an ordered to-many's order. */
static NSString *orderColumnForRelationship(NSRelationshipDescription *relationship){
   return [NSString stringWithFormat:@"Z_FOK_%@",[[relationship name] uppercaseString]];
}

static long long primaryKeyFromReferenceObject(id referenceObject){
   NSString *string=[referenceObject description];

   if([string hasPrefix:@"p"])
    string=[string substringFromIndex:1];

   return [string longLongValue];
}

static NSString *referenceObjectForPrimaryKey(long long primaryKey){
   return [NSString stringWithFormat:@"%lld",primaryKey];
}

/* [entity _isKindOfEntity:] is private to the framework; the public
   equivalent is a walk up the superentity chain. */
static BOOL entityIsKindOfEntity(NSEntityDescription *entity,NSEntityDescription *other){
   for(NSEntityDescription *check=entity;check!=nil;check=[check superentity])
    if([[check name] isEqualToString:[other name]])
     return YES;

   return NO;
}

/* Properties of entity including inherited ones; transient properties are
   never persisted. */
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

/* Properties stored in the root table: every property of every entity in the
   subtree rooted at entity. */
static void collectPropertiesOfEntitySubtree(NSEntityDescription *entity,NSMutableDictionary *result){
   for(NSPropertyDescription *property in [entity properties])
    if(![property isTransient] && [result objectForKey:[property name]]==nil)
     [result setObject:property forKey:[property name]];

   for(NSEntityDescription *subentity in [entity subentities])
    collectPropertiesOfEntitySubtree(subentity,result);
}

static BOOL relationshipUsesJoinTable(NSRelationshipDescription *relationship){
   NSRelationshipDescription *inverse=[relationship inverseRelationship];

   return [relationship isToMany] && (inverse==nil || [inverse isToMany]);
}

/* A derived attribute that plainly copies another attribute of the same
   table becomes a stored generated column, as it does in the SQLite store.
   The private -_generatedColumnSourceName is not available here, so the
   same shape is recognized from the public derivation expression: a
   single-segment key path naming an attribute of this entity.  Every other
   derivation form is written as an ordinary column. */
static NSString *generatedColumnSourceName(NSAttributeDescription *attribute,NSEntityDescription *entity){
   if(![attribute isKindOfClass:[NSDerivedAttributeDescription class]])
    return nil;

   NSExpression *expression=[(NSDerivedAttributeDescription *)attribute derivationExpression];

   if(expression==nil || [expression expressionType]!=NSKeyPathExpressionType)
    return nil;

   NSString *keyPath=[expression keyPath];

   if(keyPath==nil || [keyPath rangeOfString:@"."].location!=NSNotFound)
    return nil;

   NSMutableDictionary *properties=[NSMutableDictionary dictionary];

   collectPropertiesOfEntitySubtree(rootEntity(entity),properties);

   NSPropertyDescription *source=[properties objectForKey:keyPath];

   if(![source isKindOfClass:[NSAttributeDescription class]] ||
      [source isKindOfClass:[NSDerivedAttributeDescription class]])
    return nil;

   return keyPath;
}

/* ------------------------------------------------------------------ */
#pragma mark - Transformable values (public API only)
/* ------------------------------------------------------------------ */

/* -[NSAttributeDescription _dataFromTransformableValue:] and its inverse are
   private to the framework; these reproduce them through the public
   valueTransformerName.

   The non-secure keyed archiving calls below are deprecated on macOS but are
   exactly what the framework's own transformable attributes use: matching it
   is what makes a model readable from either store, so the warning is turned
   off here rather than the behavior changed. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static BOOL isUnarchiveFromDataTransformerName(NSString *name){
   return [name isEqualToString:@"NSKeyedUnarchiveFromData"] ||
          [name isEqualToString:@"NSUnarchiveFromData"] ||
          [name isEqualToString:@"NSSecureUnarchiveFromData"] ||
          [name isEqualToString:@"NSKeyedUnarchiveFromDataTransformer"] ||
          [name isEqualToString:@"NSSecureUnarchiveFromDataTransformer"];
}

static NSData *dataFromTransformableValue(NSAttributeDescription *attribute,id value){
   if(value==nil)
    return nil;

   NSString *name=[attribute valueTransformerName];

   if(name==nil || isUnarchiveFromDataTransformerName(name))
    return [NSKeyedArchiver archivedDataWithRootObject:value];

   NSValueTransformer *transformer=[NSValueTransformer valueTransformerForName:name];

   if(transformer==nil){
    NSLog(@"No NSValueTransformer registered with name %@ for attribute %@",name,[attribute name]);
    return nil;
   }

   /* A registered transformer that is itself an unarchiving transformer
      (data to object) is applied in reverse. */
   if(isUnarchiveFromDataTransformerName(NSStringFromClass([transformer class])))
    return [transformer reverseTransformedValue:value];

   id transformed=[transformer transformedValue:value];

   if(![transformed isKindOfClass:[NSData class]]){
    NSLog(@"Value transformer %@ for attribute %@ did not produce NSData",name,[attribute name]);
    return nil;
   }

   return transformed;
}

static id transformableValueFromData(NSAttributeDescription *attribute,NSData *data){
   if(data==nil)
    return nil;

   NSString *name=[attribute valueTransformerName];

   if(name==nil || isUnarchiveFromDataTransformerName(name))
    return [NSKeyedUnarchiver unarchiveObjectWithData:data];

   NSValueTransformer *transformer=[NSValueTransformer valueTransformerForName:name];

   if(transformer==nil){
    NSLog(@"No NSValueTransformer registered with name %@ for attribute %@",name,[attribute name]);
    return nil;
   }

   if(isUnarchiveFromDataTransformerName(NSStringFromClass([transformer class])))
    return [transformer transformedValue:data];

   if([[transformer class] allowsReverseTransformation])
    return [transformer reverseTransformedValue:data];

   return nil;
}

#pragma clang diagnostic pop

/* ------------------------------------------------------------------ */
#pragma mark - Running statements
/* ------------------------------------------------------------------ */

@implementation CDSQLStore (CDSQLStatements)
/* (declared in the main interface; implemented here to keep the engine
   beside the driver hooks it calls) */

/* The rules for retrying, which are the same whichever database is at the
   other end: a statement issued inside a transaction is never replayed,
   because the transaction it belonged to is gone and repeating one
   statement of it would write a fragment of a save; and COMMIT and ROLLBACK
   are never replayed, because an empty COMMIT on a fresh connection
   succeeds and would report a save that never happened.
 
   The store tracks its own transaction rather than asking the driver after
   the fact: a dropped connection cannot say what was open when it died. */
-(id<CDSQLResult>)execute:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
   BOOL             opens=[sql isEqualToString:@"BEGIN"];
   BOOL             closes=([sql isEqualToString:@"COMMIT"] || [sql isEqualToString:@"ROLLBACK"]);
   BOOL             retryable=(!_inTransaction && !closes);
   NSError         *attemptError=nil;
   id<CDSQLResult>  result=[self runSQL:sql parameters:parameters error:&attemptError];

   if(result==nil && retryable && [self connectionIsLost] && [self reopenConnectionWithError:NULL])
    result=[self runSQL:sql parameters:parameters error:&attemptError];

   /* A transaction ends whether or not its COMMIT or ROLLBACK got through:
      if the connection died, the server has already rolled it back. */
   if(closes)
    _inTransaction=NO;
   else if(opens && result!=nil)
    _inTransaction=YES;

   if(result==nil && error!=NULL)
    *error=attemptError;

   return result;
}

-(BOOL)command:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
   return ([self execute:sql parameters:parameters error:error]!=nil);
}

-(BOOL)command:(NSString *)sql parameters:(NSArray *)parameters affected:(long long *)affected error:(NSError **)error {
   if(![self command:sql parameters:parameters error:error])
    return NO;

   if(affected!=NULL)
    *affected=[self rowsAffected];

   return YES;
}

-(BOOL)tableExists:(NSString *)name {
   id<CDSQLResult> result=[self execute:[self tableExistsSQL] parameters:[NSArray arrayWithObject:name] error:NULL];

   return (result!=nil && [result rowCount]>0);
}

/* The bookkeeping tables are described in the same terms as a model's
   columns, so a dialect that spells "integer" or "bytea" its own way needs
   to say so only once. */
-(NSString *)_integerType {
   return [self columnTypeForAttributeType:NSInteger32AttributeType];
}

-(NSString *)_bigIntegerType {
   return [self columnTypeForAttributeType:NSInteger64AttributeType];
}

-(NSString *)_textType {
   return [self columnTypeForAttributeType:NSStringAttributeType];
}

-(NSString *)_blobType {
   return [self columnTypeForAttributeType:NSBinaryDataAttributeType];
}

-(NSString *)_doubleType {
   return [self columnTypeForAttributeType:NSDoubleAttributeType];
}

-(NSString *)quoted:(NSString *)identifier {
   return quoted(identifier);
}

-(NSString *)schemaName {
   return _schemaName;
}

-(long long)creationLockKey {
   return [self lockKeyForName:[self schemaName]];
}

-(long long)lockKeyForName:(NSString *)name {
   return advisoryLockKeyForSchema(name);
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - Values to and from text parameters
/* ------------------------------------------------------------------ */

/* Binary values travel to the driver as themselves; each driver writes the
   literal its database expects. */
static id parameterFromData(NSData *data){
   return data;
}

/* The text parameter for value, or nil when the column should be NULL. */
static id textParameterForAttribute(NSAttributeDescription *attribute,id value){
   if(value==nil || value==[NSNull null])
    return nil;

   switch([attribute attributeType]){
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
     return [NSString stringWithFormat:@"%lld",[value longLongValue]];
    case NSBooleanAttributeType:
     return [value boolValue]?@"1":@"0";   /* PostgreSQL and MySQL both read these */
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
     return [NSString stringWithFormat:@"%.17g",[value doubleValue]];
    case NSDecimalAttributeType:
     return [value description];
    case NSDateAttributeType:
     /* Stored as the reference-date interval, like the SQLite store: the
        round trip is exact and ordering is the natural numeric one. */
     return [NSString stringWithFormat:@"%.17g",[value timeIntervalSinceReferenceDate]];
    case NSBinaryDataAttributeType:
     return parameterFromData(value);
    case NSStringAttributeType:
     return [value description];
    case NSUUIDAttributeType:
     return [(NSUUID *)value UUIDString];
    case NSURIAttributeType:
     return [(NSURL *)value absoluteString];
    case NSTransformableAttributeType:
    default: {
     NSData *data=dataFromTransformableValue(attribute,value);

     return (data!=nil)?parameterFromData(data):nil;
    }
   }
}

static id attributeValueFromResult(id<CDSQLResult> result,int row,int column,NSAttributeDescription *attribute){
   if([result isNullAtRow:row column:column])
    return nil;

   switch([attribute attributeType]){
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
     return [NSNumber numberWithLongLong:[result longLongAtRow:row column:column]];
    case NSBooleanAttributeType: {
     /* PostgreSQL answers t/f, MySQL 1/0; both are written as 1/0. */
     NSString *text=[result stringAtRow:row column:column];
     unichar   first=([text length]>0)?[text characterAtIndex:0]:'0';

     return [NSNumber numberWithBool:(first=='t' || first=='T' || first=='1' || first=='y' || first=='Y')];
    }
    case NSDoubleAttributeType:
     return [NSNumber numberWithDouble:[result doubleAtRow:row column:column]];
    case NSFloatAttributeType:
     return [NSNumber numberWithFloat:(float)[result doubleAtRow:row column:column]];
    case NSDecimalAttributeType:
     return [NSDecimalNumber decimalNumberWithString:[result stringAtRow:row column:column]];
    case NSDateAttributeType:
     return [NSDate dateWithTimeIntervalSinceReferenceDate:[result doubleAtRow:row column:column]];
    case NSBinaryDataAttributeType:
     return [result dataAtRow:row column:column];
    case NSStringAttributeType:
     return [result stringAtRow:row column:column];
    case NSUUIDAttributeType:
     return [[[NSUUID alloc] initWithUUIDString:[result stringAtRow:row column:column]] autorelease];
    case NSURIAttributeType:
     return [NSURL URLWithString:[result stringAtRow:row column:column]];
    case NSTransformableAttributeType:
    default:
     return transformableValueFromData(attribute,[result dataAtRow:row column:column]);
   }
}


/* Attribute types whose stored representation compares exactly like the
   in-memory value.  Unlike the SQLite store, numeric and uuid columns keep
   their own types here, so decimals compare exactly too; binary and
   transformable values remain non-canonical blobs and are filtered in
   memory. */
static BOOL attributeComparesExactlyInSQL(NSAttributeDescription *attribute){
   switch([attribute attributeType]){
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSBooleanAttributeType:
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
    case NSDecimalAttributeType:
    case NSDateAttributeType:
    case NSStringAttributeType:
     return YES;
    default:
     return NO;
   }
}

/* Types whose stored form compares EQUAL exactly, which is a wider set than
   the one that ORDERS exactly: a UUID is stored as itself and bytes are
   stored as themselves, so = and IN are exact for both even though < and >
   would mean nothing.
 
   Transformable values are not here: what is stored is whatever the value
   transformer produced, and two equal objects need not archive to the same
   bytes. */
static BOOL attributeEqualityIsExactInSQL(NSAttributeDescription *attribute){
   switch([attribute attributeType]){
    case NSUUIDAttributeType:
    case NSBinaryDataAttributeType:
     return YES;
    default:
     return attributeComparesExactlyInSQL(attribute);
   }
}

/* A stable 64-bit key for the advisory locks that serialize creating a
   store, derived from the schema it lives in (FNV-1a).  Two processes
   opening the same brand-new store race to create it otherwise: SQLite
   hides that behind its file lock, a server does not. */
static long long advisoryLockKeyForSchema(NSString *schema){
   const char        *bytes=[(schema!=nil)?schema:@"public" UTF8String];
   unsigned long long hash=14695981039346656037ULL;

   while(*bytes!='\0'){
    hash^=(unsigned char)*bytes++;
    hash*=1099511628211ULL;
   }

   return (long long)hash;
}

/* ------------------------------------------------------------------ */
#pragma mark - Store metadata
/* ------------------------------------------------------------------ */

@implementation CDSQLStore (CDSQLMetadata)

-(NSDictionary *)_readMetadataWithError:(NSError **)error {
   if(![self tableExists:@"Z_METADATA"]){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreInvalidTypeError userInfo:[NSDictionary dictionaryWithObject:@"The database does not hold a CoreData store (missing Z_METADATA)" forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   id<CDSQLResult> result=[self execute:@"SELECT \"Z_UUID\", \"Z_PLIST\" FROM \"Z_METADATA\" LIMIT 1" parameters:nil error:error];

   if(result==nil)
    return nil;

   NSMutableDictionary *metadata=[NSMutableDictionary dictionary];

   if((int)[result rowCount]>0){
    if(![result isNullAtRow:0 column:1]){
     NSData       *plistData=[result dataAtRow:0 column:1];
     NSDictionary *plist=(plistData!=nil)?[NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:NULL error:NULL]:nil;

     if([plist isKindOfClass:[NSDictionary class]])
      [metadata addEntriesFromDictionary:plist];
    }

    if(![result isNullAtRow:0 column:0])
     [metadata setObject:[result stringAtRow:0 column:0] forKey:NSStoreUUIDKey];
   }

   
   [metadata setObject:[self type] forKey:NSStoreTypeKey];

   return metadata;
}

-(BOOL)_writeMetadata:(NSDictionary *)metadata error:(NSError **)error {
   NSMutableDictionary *plist=[NSMutableDictionary dictionaryWithDictionary:metadata];

   [plist removeObjectForKey:NSStoreUUIDKey];
   [plist removeObjectForKey:NSStoreTypeKey];

   NSData *plistData=[NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];

   if(plistData==nil)
    return NO;

   NSString *uuid=[metadata objectForKey:NSStoreUUIDKey];
   NSArray  *parameters=[NSArray arrayWithObjects:
                            [NSString stringWithFormat:@"%d",CDSQLStoreMetadataVersion],
                            (uuid!=nil)?(id)uuid:(id)[NSNull null],
                            parameterFromData(plistData),
                            nil];

   NSString *sql=[NSString stringWithFormat:@"INSERT INTO \"Z_METADATA\" (\"Z_VERSION\", \"Z_UUID\", \"Z_PLIST\") VALUES ($1, $2, $3)%@",
                                            [self upsertClauseForColumns:[NSArray arrayWithObjects:@"\"Z_UUID\"",@"\"Z_PLIST\"",nil]
                                                              keyColumns:[NSArray arrayWithObject:@"\"Z_VERSION\""]]];

   return [self command:sql parameters:parameters error:error];
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - Persistent history: what this needs from the framework
/* ------------------------------------------------------------------ */

/* Everything else in this store is written against public API, so that the
   same source builds against Apple's CoreData and can be arbitrated there.
   Persistent history is the one feature that cannot be: nothing public says
   whether a history request is a fetch or a purge, nor what it is anchored
   to.  Apple publishes `token`, `fetchRequest` and `resultType` and no more,
   the two kinds of request are the same class with the same requestType, and
   the framework here keeps the same three answers to itself.

   FreeCoreData answers both halves of that publicly, as additions of its
   own: -isPurgeRequest, -anchorDate and -anchorTransactionNumber for reading
   a request, and factory methods on the transaction, change and token
   classes for building what a store hands back.  Nothing here reaches into
   the framework.
 
   The declarations are repeated here rather than imported so that this file
   still compiles against Apple's CoreData, which has none of them; every
   call is guarded by historySupportedByFramework(), which is false there,
   and history requests are then reported as unsupported.

   The store side of the arrangement needs nothing special: the coordinator
   asks each store for its history position by respondsToSelector:, so
   implementing -_historyTrackingEnabled and -_lastHistoryTransactionNumber
   is all it takes to join in. */

/* Reading the request: public API in FreeCoreData, absent from Apple's, so
   it is declared here to compile against either. */
@interface NSPersistentHistoryChangeRequest (CDFreeCoreDataAPI)
-(BOOL)isPurgeRequest;
-(NSDate *)anchorDate;
-(int64_t)anchorTransactionNumber;
@end

@interface NSPersistentHistoryToken (CDFreeCoreDataAPI)
+(instancetype)tokenWithTransactionNumbersByStoreIdentifier:(NSDictionary *)numbers;
-(int64_t)transactionNumberForStoreIdentifier:(NSString *)identifier;
@end

@interface NSPersistentHistoryTransaction (CDFreeCoreDataAPI)
+(instancetype)transactionWithNumber:(int64_t)number
                           timestamp:(NSDate *)timestamp
                              author:(NSString *)author
                         contextName:(NSString *)contextName
                           processID:(NSString *)processID
                            bundleID:(NSString *)bundleID
                     storeIdentifier:(NSString *)storeIdentifier
                             changes:(NSArray *)changes;
@end

@interface NSPersistentHistoryChange (CDFreeCoreDataAPI)
+(instancetype)changeWithID:(int64_t)changeID
                       type:(NSPersistentHistoryChangeType)type
                   objectID:(NSManagedObjectID *)objectID
          updatedProperties:(NSSet *)updatedProperties
                  tombstone:(NSDictionary *)tombstone;
@end

/* Whether the CoreData this store is running against publishes what a store
   needs to implement history: FreeCoreData yes, Apple's no. */
static BOOL historySupportedByFramework(void){
   static BOOL checked=NO;
   static BOOL available=NO;

   if(!checked){
    available=[NSPersistentHistoryChangeRequest instancesRespondToSelector:@selector(isPurgeRequest)] &&
              [NSPersistentHistoryTransaction respondsToSelector:@selector(transactionWithNumber:timestamp:author:contextName:processID:bundleID:storeIdentifier:changes:)] &&
              [NSPersistentHistoryChange respondsToSelector:@selector(changeWithID:type:objectID:updatedProperties:tombstone:)] &&
              [NSPersistentHistoryToken respondsToSelector:@selector(tokenWithTransactionNumbersByStoreIdentifier:)];
    checked=YES;
   }

   return available;
}

/* ------------------------------------------------------------------ */
#pragma mark - Batch results
/* ------------------------------------------------------------------ */

/* The framework builds these with an initializer of its own, which is
   private.  Nothing stops a store outside the framework from producing one
   the public way: the classes declare no designated initializer, do not mark
   -init unavailable, and expose -result/-resultType as readonly properties,
   so a subclass that carries its own values and answers those two messages
   is a perfectly ordinary NSBatchUpdateResult.  The persistent store
   coordinator hands whatever the store returns straight back to the caller,
   on this framework and on Apple's alike. */

@interface CDBatchInsertResult : NSBatchInsertResult {
   id _value;
   NSBatchInsertRequestResultType _type;
}
-(instancetype)initWithValue:(id)value type:(NSBatchInsertRequestResultType)type;
@end

@implementation CDBatchInsertResult

-(instancetype)initWithValue:(id)value type:(NSBatchInsertRequestResultType)type {
   if((self=[super init])==nil)
    return nil;
   _value=[value retain];
   _type=type;
   return self;
}

-(void)dealloc { [_value release]; [super dealloc]; }
-(id)result { return _value; }
-(NSBatchInsertRequestResultType)resultType { return _type; }

@end

@interface CDBatchUpdateResult : NSBatchUpdateResult {
   id _value;
   NSBatchUpdateRequestResultType _type;
}
-(instancetype)initWithValue:(id)value type:(NSBatchUpdateRequestResultType)type;
@end

@implementation CDBatchUpdateResult

-(instancetype)initWithValue:(id)value type:(NSBatchUpdateRequestResultType)type {
   if((self=[super init])==nil)
    return nil;
   _value=[value retain];
   _type=type;
   return self;
}

-(void)dealloc { [_value release]; [super dealloc]; }
-(id)result { return _value; }
-(NSBatchUpdateRequestResultType)resultType { return _type; }

@end

@interface CDBatchDeleteResult : NSBatchDeleteResult {
   id _value;
   NSBatchDeleteRequestResultType _type;
}
-(instancetype)initWithValue:(id)value type:(NSBatchDeleteRequestResultType)type;
@end

@implementation CDBatchDeleteResult

-(instancetype)initWithValue:(id)value type:(NSBatchDeleteRequestResultType)type {
   if((self=[super init])==nil)
    return nil;
   _value=[value retain];
   _type=type;
   return self;
}

-(void)dealloc { [_value release]; [super dealloc]; }
-(id)result { return _value; }
-(NSBatchDeleteRequestResultType)resultType { return _type; }

@end

@interface CDPersistentHistoryResult : NSPersistentHistoryResult {
   id _value;
   NSPersistentHistoryResultType _type;
}
-(instancetype)initWithValue:(id)value type:(NSPersistentHistoryResultType)type;
@end

@implementation CDPersistentHistoryResult

-(instancetype)initWithValue:(id)value type:(NSPersistentHistoryResultType)type {
   if((self=[super init])==nil)
    return nil;
   _value=[value retain];
   _type=type;
   return self;
}

-(void)dealloc { [_value release]; [super dealloc]; }
-(id)result { return _value; }
-(NSPersistentHistoryResultType)resultType { return _type; }

@end

@implementation CDSQLStore

/* ------------------------------------------------------------------ */
#pragma mark - Lifecycle
/* ------------------------------------------------------------------ */

-initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root configurationName:(NSString *)name URL:(NSURL *)url options:(NSDictionary *)options {
   if((self=[super initWithPersistentStoreCoordinator:root configurationName:name URL:url options:options])==nil)
    return nil;

   _schemaName=[[options objectForKey:CDSQLStoreSchemaNameOption] copy];
   _entityIDs=[[NSMutableDictionary alloc] init];
   _entityNamesByID=[[NSMutableDictionary alloc] init];
   _rowVersions=[[NSMutableDictionary alloc] init];

   return self;
}

-(void)dealloc {
   [self closeConnection];
   [_schemaName release];
   [_entityIDs release];
   [_entityNamesByID release];
   [_rowVersions release];
   [super dealloc];
}

/* Sugar for the migration code, which issues a lot of one-off DDL. */
-(BOOL)_command:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
   return [self command:sql parameters:parameters error:error];
}

-(BOOL)isInTransaction {
   return _inTransaction;
}

-(void)setInTransaction:(BOOL)flag {
   _inTransaction=flag;
}

/* The class-side entry points need a connection but have no store: they
   open one of their own, which is also how they reach the driver and the
   dialect a subclass supplies. */
+(instancetype)_temporaryStoreForURL:(NSURL *)url options:(NSDictionary *)options error:(NSError **)error {
   CDSQLStore *store=[[[self alloc] initWithPersistentStoreCoordinator:nil configurationName:nil URL:url options:options] autorelease];

   if(![store openConnectionWithURL:url options:options error:error])
    return nil;

   return store;
}

+(NSDictionary *)metadataForPersistentStoreWithURL:(NSURL *)url error:(NSError **)error {
   CDSQLStore *store=[self _temporaryStoreForURL:url options:nil error:error];

   if(store==nil)
    return nil;

   NSDictionary *metadata=[store _readMetadataWithError:error];

   [store closeConnection];

   return metadata;
}

+(BOOL)setMetadata:(NSDictionary *)metadata forPersistentStoreWithURL:(NSURL *)url error:(NSError **)error {
   CDSQLStore *store=[self _temporaryStoreForURL:url options:nil error:error];

   if(store==nil)
    return NO;

   BOOL result=[store _writeMetadata:metadata error:error];

   [store closeConnection];

   return result;
}

-(void)setMetadata:(NSDictionary *)value {
   [super setMetadata:value];

   /* Persist metadata changes immediately, so version stamps survive
      without an explicit save. */
   if([self tableExists:@"Z_METADATA"])
    [self _writeMetadata:[self metadata] error:NULL];
}

+(BOOL)destroyStoreAtURL:(NSURL *)url options:(NSDictionary *)options error:(NSError **)error {
   CDSQLStore *store=[self _temporaryStoreForURL:url options:options error:error];

   if(store==nil)
    return NO;

   BOOL result=[store _destroyContentsWithError:error];

   [store closeConnection];

   return result;
}

/* Everything this store owns: the whole schema when it has one of its own
   (which is the subclass's business, since a "schema" is a database in some
   databases), otherwise the tables it created. */
-(BOOL)_destroyContentsWithError:(NSError **)error {
   if([self schemaName]!=nil)
    return [self dropSchemaWithError:error];

   id<CDSQLResult> tables=[self execute:[self tablesInSchemaSQL] parameters:nil error:error];

   if(tables==nil)
    return NO;

   NSUInteger i,count=[tables rowCount];

   for(i=0;i<count;i++){
    NSString *name=[tables stringAtRow:i column:0];

    if(![name hasPrefix:@"Z"])
     continue;
    if(![self command:[self dropTableSQLForTable:name] parameters:nil error:error])
     return NO;
   }

   return YES;
}

/* ------------------------------------------------------------------ */
#pragma mark - Entity/schema bookkeeping
/* ------------------------------------------------------------------ */

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

-(void)_collectEntityIDsOfEntity:(NSEntityDescription *)entity into:(NSMutableArray *)result {
   [result addObject:[NSNumber numberWithLongLong:[self _entityIDForEntity:entity]]];

   for(NSEntityDescription *subentity in [entity subentities])
    [self _collectEntityIDsOfEntity:subentity into:result];
}

/* The join table of a many-to-many (or inverse-less to-many) relationship,
   from the point of view of its owner.  Both sides of a many-to-many share
   one table; the canonical side is the one with the smaller entity ID (ties
   broken by relationship name). */
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

   if(inverse!=nil)
    ownerColumn=[NSString stringWithFormat:@"Z_%lld%@",ownerID,[[inverse name] uppercaseString]];
   else
    ownerColumn=[NSString stringWithFormat:@"Z_%lld%@",ownerID,[[owner name] uppercaseString]];

   destinationColumn=[NSString stringWithFormat:@"Z_%lld%@",destinationID,[[relationship name] uppercaseString]];

   return [NSDictionary dictionaryWithObjectsAndKeys:table,@"table",ownerColumn,@"ownerColumn",destinationColumn,@"destinationColumn",nil];
}

/* ------------------------------------------------------------------ */
#pragma mark - Schema creation and loading
/* ------------------------------------------------------------------ */

/* The columns a root entity's table holds, as {name, type, generatedFrom},
   in the order they are created.  Schema creation and schema migration both
   read the layout from here, so the two cannot drift apart. */
-(NSArray *)_columnSpecsForRootEntity:(NSEntityDescription *)entity amongEntities:(NSArray *)storeEntities {
   NSMutableArray      *specs=[NSMutableArray array];
   NSMutableDictionary *properties=[NSMutableDictionary dictionary];

   [specs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"Z_PK",@"name",[self _bigIntegerType],@"type",nil]];
   [specs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"Z_ENT",@"name",[self _integerType],@"type",nil]];
   [specs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"Z_OPT",@"name",[self _integerType],@"type",nil]];

   collectPropertiesOfEntitySubtree(entity,properties);

   for(NSString *name in [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)]){
    NSPropertyDescription *property=[properties objectForKey:name];

    if([property isKindOfClass:[NSAttributeDescription class]]){
     NSAttributeDescription *attribute=(NSAttributeDescription *)property;
     NSString               *source=generatedColumnSourceName(attribute,entity);
     NSMutableDictionary    *spec=[NSMutableDictionary dictionaryWithObjectsAndKeys:
                                      columnNameForProperty(name),@"name",
                                      [self columnTypeForAttributeType:[attribute attributeType]],@"type",
                                      nil];

     if(source!=nil)
      [spec setObject:columnNameForProperty(source) forKey:@"generatedFrom"];
     [specs addObject:spec];
    }
    else if([property isKindOfClass:[NSRelationshipDescription class]] && ![(NSRelationshipDescription *)property isToMany])
     [specs addObject:[NSDictionary dictionaryWithObjectsAndKeys:columnNameForProperty(name),@"name",[self _bigIntegerType],@"type",nil]];
   }

   /* An ordered foreign-key to-many keeps its order in a hidden Z_FOK_
      column on the destination (many-side) table. */
   for(NSEntityDescription *other in storeEntities)
    for(NSRelationshipDescription *incoming in [[other relationshipsByName] allValues])
     if([incoming isToMany] && [incoming isOrdered] &&
        !relationshipUsesJoinTable(incoming) &&
        rootEntity([incoming destinationEntity])==entity)
      [specs addObject:[NSDictionary dictionaryWithObjectsAndKeys:orderColumnForRelationship(incoming),@"name",[self _bigIntegerType],@"type",nil]];

   return specs;
}

/* The DDL for one column of the layout above. */
-(NSString *)columnDefinitionFromSpec:(NSDictionary *)spec {
   NSString *name=[spec objectForKey:@"name"];
   NSString *type=[spec objectForKey:@"type"];
   NSString *generatedFrom=[spec objectForKey:@"generatedFrom"];

   if([name isEqualToString:@"Z_PK"])
    return [NSString stringWithFormat:@"%@ %@ PRIMARY KEY",quoted(name),type];
   if(generatedFrom!=nil)
    return [NSString stringWithFormat:@"%@ %@ GENERATED ALWAYS AS (%@) STORED",quoted(name),type,quoted(generatedFrom)];

   return [NSString stringWithFormat:@"%@ %@",quoted(name),type];
}

-(BOOL)_createSchema:(NSError **)error {
   NSMutableDictionary *entitiesByName=[NSMutableDictionary dictionary];
   NSMutableArray      *sortedEntities=[NSMutableArray array];

   for(NSEntityDescription *entity in [self _storeEntities])
    [entitiesByName setObject:entity forKey:[entity name]];

   for(NSString *name in [[entitiesByName allKeys] sortedArrayUsingSelector:@selector(compare:)])
    [sortedEntities addObject:[entitiesByName objectForKey:name]];

   /* Entity IDs are assigned in name order, starting at 1. */
   long long nextID=1;

   for(NSEntityDescription *entity in sortedEntities)
    [self _registerEntityID:nextID++ forName:[entity name]];

   if(![self command:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS \"Z_METADATA\" (\"Z_VERSION\" %@ PRIMARY KEY, \"Z_UUID\" %@, \"Z_PLIST\" %@)",[self _integerType],[self _textType],[self _blobType]] parameters:nil error:error])
    return NO;

   if(![self command:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS \"Z_PRIMARYKEY\" (\"Z_ENT\" %@ PRIMARY KEY, \"Z_NAME\" %@, \"Z_SUPER\" %@, \"Z_MAX\" %@)",[self _integerType],[self _textType],[self _integerType],[self _bigIntegerType]] parameters:nil error:error])
    return NO;

   for(NSEntityDescription *entity in sortedEntities){
    NSEntityDescription *superentity=[entity superentity];
    long long            superID=(superentity!=nil)?[self _entityIDForEntity:superentity]:0;
    NSArray             *parameters=[NSArray arrayWithObjects:
                                        [NSString stringWithFormat:@"%lld",[self _entityIDForEntity:entity]],
                                        [entity name],
                                        [NSString stringWithFormat:@"%lld",superID],
                                        nil];

    if(![self command:@"INSERT INTO \"Z_PRIMARYKEY\" (\"Z_ENT\", \"Z_NAME\", \"Z_SUPER\", \"Z_MAX\") VALUES ($1, $2, $3, 0)" parameters:parameters error:error])
     return NO;
   }

   NSMutableSet *createdJoinTables=[NSMutableSet set];

   for(NSEntityDescription *entity in sortedEntities){
    /* One table per root entity, holding the whole entity subtree. */
    if([entity superentity]==nil){
     NSMutableArray *columns=[NSMutableArray array];

     for(NSDictionary *spec in [self _columnSpecsForRootEntity:entity amongEntities:sortedEntities])
      [columns addObject:[self columnDefinitionFromSpec:spec]];

     NSString *sql=[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (%@)",quoted(tableNameForEntity(entity)),[columns componentsJoinedByString:@", "]];

     if(![self command:sql parameters:nil error:error])
      return NO;
    }

    /* Join tables for many-to-many (and inverse-less to-many). */
    for(NSRelationshipDescription *relationship in [[entity relationshipsByName] allValues]){
     if(!relationshipUsesJoinTable(relationship))
      continue;

     NSDictionary *join=[self _joinSpecForRelationship:relationship];
     NSString     *table=[join objectForKey:@"table"];

     if([createdJoinTables containsObject:table])
      continue;
     [createdJoinTables addObject:table];

     NSMutableString *joinColumns=[NSMutableString stringWithFormat:@"%@ %@, %@ %@",
                                                                    quoted([join objectForKey:@"ownerColumn"]),[self _bigIntegerType],
                                                                    quoted([join objectForKey:@"destinationColumn"]),[self _bigIntegerType]];

     if([relationship isOrdered])
      [joinColumns appendFormat:@", %@ %@",quoted(orderColumnForRelationship(relationship)),[self _bigIntegerType]];
     if([[relationship inverseRelationship] isOrdered])
      [joinColumns appendFormat:@", %@ %@",quoted(orderColumnForRelationship([relationship inverseRelationship])),[self _bigIntegerType]];

     NSString *sql=[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (%@, PRIMARY KEY (%@, %@))",
                                              quoted(table),joinColumns,
                                              quoted([join objectForKey:@"ownerColumn"]),
                                              quoted([join objectForKey:@"destinationColumn"])];

     if(![self command:sql parameters:nil error:error])
      return NO;
    }
   }

   return YES;
}

-(BOOL)_loadEntityIDs:(NSError **)error {
   id<CDSQLResult> result=[self execute:@"SELECT \"Z_ENT\", \"Z_NAME\" FROM \"Z_PRIMARYKEY\"" parameters:nil error:error];

   if(result==nil)
    return NO;

   int i,count=(int)[result rowCount];

   for(i=0;i<count;i++)
    if(![result isNullAtRow:i column:1])
     [self _registerEntityID:[result longLongAtRow:i column:0]
                     forName:[result stringAtRow:i column:1]];

   
   return YES;
}

-(BOOL)loadMetadata:(NSError **)error {
   if(![self openConnectionWithURL:[self URL] options:[self options] error:error])
    return NO;

   id trackingOption=[[self options] objectForKey:NSPersistentHistoryTrackingKey];
   id postOption=[[self options] objectForKey:NSPersistentStoreRemoteChangeNotificationPostOptionKey];

   _historyTracking=[trackingOption respondsToSelector:@selector(boolValue)] && [trackingOption boolValue];
   _postsRemoteChangeNotification=[postOption respondsToSelector:@selector(boolValue)] && [postOption boolValue];

   /* Opening is done inside one transaction holding an advisory lock on
      this schema, so that two processes opening the same new store cannot
      both decide it is empty and both create it.  The lock is taken for the
      transaction, so it is released by the COMMIT (or by a rollback, or by
      the connection dying) without any unlock of ours.
 
      Everything the winner writes - the tables, the Z_PRIMARYKEY rows and
      the metadata - lands in that one transaction, so the loser either sees
      a store with nothing in it (and takes the lock next) or sees all of
      it. */
   if(![self command:@"BEGIN" parameters:nil error:error])
    return NO;

   if(![self takeCreationLockWithError:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    [self releaseCreationLock];
    return NO;
   }

   if([self tableExists:@"Z_METADATA"]){
    NSDictionary *metadata=[self _readMetadataWithError:error];

    if(metadata==nil){
     [self command:@"ROLLBACK" parameters:nil error:NULL];
     [self releaseCreationLock];
     return NO;
    }

    [super setMetadata:metadata];

    if(![self _loadEntityIDs:error]){
     [self command:@"ROLLBACK" parameters:nil error:NULL];
     [self releaseCreationLock];
     return NO;
    }

    /* The store was written by some model; if it was not this one, either
       bring the schema into line or refuse, as the coordinator would.  It
       happens inside the same locked transaction as creation, so two
       clients opening an out-of-date store cannot migrate it at once. */
    if([self _needsMigrationForMetadata:metadata]){
     id migrateOption=[[self options] objectForKey:CDSQLStoreMigrateSchemaOption];

     if(!([migrateOption respondsToSelector:@selector(boolValue)] && [migrateOption boolValue])){
      if(error!=NULL)
       *error=[NSError errorWithDomain:NSCocoaErrorDomain
                                  code:NSPersistentStoreIncompatibleVersionHashError
                              userInfo:[NSDictionary dictionaryWithObject:@"The model used to open the store is incompatible with the one used to create the store.  Pass CDSQLStoreMigrateSchemaOption to migrate it in place."
                                                                   forKey:NSLocalizedDescriptionKey]];
      [self command:@"ROLLBACK" parameters:nil error:NULL];
      [self releaseCreationLock];
      return NO;
     }

     if(![self _migrateSchemaWithError:error]){
      [self command:@"ROLLBACK" parameters:nil error:NULL];
      [self releaseCreationLock];
      return NO;
     }
    }

    if(![self _prepareHistoryTracking:error]){
     [self command:@"ROLLBACK" parameters:nil error:NULL];
     [self releaseCreationLock];
     return NO;
    }

    BOOL committed=[self command:@"COMMIT" parameters:nil error:error];

    [self releaseCreationLock];

    return committed;
   }

   /* An empty database: create the schema and stamp the metadata with the
      version hashes of the model in use, so compatibility can be checked
      when the store is reopened later. */
   if(![self _createSchema:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    [self releaseCreationLock];
    return NO;
   }

   NSManagedObjectModel *model=[[self persistentStoreCoordinator] managedObjectModel];
   NSMutableDictionary  *versionHashes=[NSMutableDictionary dictionary];

   for(NSEntityDescription *entity in [self _storeEntities])
    [versionHashes setObject:[entity versionHash] forKey:[entity name]];

   NSDictionary *metadata=[NSDictionary dictionaryWithObjectsAndKeys:
                              [self type],NSStoreTypeKey,
                              [[NSUUID UUID] UUIDString],NSStoreUUIDKey,
                              versionHashes,NSStoreModelVersionHashesKey,
                              [[model versionIdentifiers] allObjects],NSStoreModelVersionIdentifiersKey,
                              nil];

   [super setMetadata:metadata];

   if(![self _writeMetadata:metadata error:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    [self releaseCreationLock];
    return NO;
   }

   if(![self _prepareHistoryTracking:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    [self releaseCreationLock];
    return NO;
   }

   if(![self command:@"COMMIT" parameters:nil error:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    [self releaseCreationLock];
    return NO;
   }

   [self releaseCreationLock];

   return YES;
}

/* ------------------------------------------------------------------ */
#pragma mark - Predicates
/* ------------------------------------------------------------------ */

/* A bound parameter is the text form of the value; the placeholder is its
   1-based position, which is why bindings are appended in the same order the
   SQL mentioning them is built. */
static NSString *placeholderForBinding(NSMutableArray *bindings,NSPropertyDescription *property,id value){
   NSString *text;

   if([property isKindOfClass:[NSAttributeDescription class]])
    text=textParameterForAttribute((NSAttributeDescription *)property,value);
   else /* to-one relationship: the destination row's Z_PK */
    text=[NSString stringWithFormat:@"%lld",[value longLongValue]];

   [bindings addObject:(text!=nil)?(id)text:(id)[NSNull null]];

   return [NSString stringWithFormat:@"$%lu",(unsigned long)[bindings count]];
}

/* Some NSPredicate implementations hand back constant values still wrapped
   in constant NSExpressions; unwrap them. */
static id resolvedConstantValue(id value){
   while([value isKindOfClass:[NSExpression class]] &&
         [(NSExpression *)value expressionType]==NSConstantValueExpressionType)
    value=[(NSExpression *)value constantValue];

   return value;
}

/* Whether an expression is SELF - the row itself.
 
   Apple reports NSEvaluatedObjectExpressionType for it.  GNUstep's base
   builds a GSEvaluatedObjectExpression whose -expressionType answers 0
   (NSConstantValueExpressionType), so the type alone is not a reliable
   test; both render as "SELF", and a key path literally named SELF means
   the same thing anyway. */
static BOOL expressionIsSelf(NSExpression *expression){
   if([expression expressionType]==NSEvaluatedObjectExpressionType)
    return YES;

   return [[expression description] isEqualToString:@"SELF"];
}

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

/* How a wildcard match is spelled, and whether case folding is a matter of
   operator or of collation, is the dialect's business; what has to be
   escaped inside the pattern is not. */
static NSString *escapedLikePattern(NSString *string){
   NSMutableString *result=[NSMutableString stringWithString:string];

   [result replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0,[result length])];
   [result replaceOccurrencesOfString:@"%" withString:@"\\%" options:0 range:NSMakeRange(0,[result length])];
   [result replaceOccurrencesOfString:@"_" withString:@"\\_" options:0 range:NSMakeRange(0,[result length])];

   return result;
}


-(NSString *)_patternMatchClauseForColumn:(NSString *)column constant:(NSString *)constant caseInsensitive:(BOOL)caseInsensitive prefix:(NSString *)prefix suffix:(NSString *)suffix bindings:(NSMutableArray *)bindings attribute:(NSAttributeDescription *)attribute {
   NSString *pattern=[NSString stringWithFormat:@"%@%@%@",prefix,escapedLikePattern(constant),suffix];
   NSString *placeholder=placeholderForBinding(bindings,attribute,pattern);

   return caseInsensitive
       ?[self caseInsensitiveLikeClauseForColumn:column placeholder:placeholder]
       :[self caseSensitiveLikeClauseForColumn:column placeholder:placeholder];
}

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

/* The alias the fetched entity's own table carries, which correlated
   subqueries refer back to. */
static NSString * const CDSQLOuterAlias=@"t0";

/* Walks the relationship segments of a key path, building the FROM and
   correlation fragments of an EXISTS subquery that reaches the last
   destination table.  Answers the alias of that table (and its entity), or
   nil when the path is not one this store can follow in SQL.
 
   Correlating back to the query's own table by name - rather than joining
   it into the outer SELECT - keeps the outer query untouched: no alias to
   thread through the rest of the translator, and no DISTINCT needed when a
   to-many is crossed. */
-(NSString *)_joinChainForSegments:(NSArray *)segments
                            entity:(NSEntityDescription *)entity
                        outerTable:(NSString *)outerTable
                            prefix:(NSString *)prefix
                              from:(NSMutableArray *)from
                             where:(NSMutableArray *)where
                        lastEntity:(NSEntityDescription **)lastEntity
                     crossedToMany:(BOOL *)crossedToMany {
   NSEntityDescription *current=entity;
   NSString            *currentRef=outerTable;
   NSUInteger           index=0;

   for(NSString *segment in segments){
    NSRelationshipDescription *relationship=[propertiesForEntityChain(current) objectForKey:segment];

    if(![relationship isKindOfClass:[NSRelationshipDescription class]])
     return nil;

    NSEntityDescription *destination=[relationship destinationEntity];
    NSString            *alias=[NSString stringWithFormat:@"%@%lu",prefix,(unsigned long)index];

    if(![relationship isToMany]){
     /* A foreign key on this side points at the destination's row. */
     [from addObject:[NSString stringWithFormat:@"%@ %@",quoted(tableNameForEntity(destination)),alias]];
     [where addObject:[NSString stringWithFormat:@"%@.\"Z_PK\" = %@.%@",alias,currentRef,quoted(columnNameForProperty([relationship name]))]];
    }
    else {
     if(crossedToMany!=NULL)
      *crossedToMany=YES;

     if(relationshipUsesJoinTable(relationship)){
      NSDictionary *join=[self _joinSpecForRelationship:relationship];
      NSString     *joinAlias=[NSString stringWithFormat:@"%@t%lu",prefix,(unsigned long)index];

      [from addObject:[NSString stringWithFormat:@"%@ %@",quoted([join objectForKey:@"table"]),joinAlias]];
      [from addObject:[NSString stringWithFormat:@"%@ %@",quoted(tableNameForEntity(destination)),alias]];
      [where addObject:[NSString stringWithFormat:@"%@.%@ = %@.\"Z_PK\"",joinAlias,quoted([join objectForKey:@"ownerColumn"]),currentRef]];
      [where addObject:[NSString stringWithFormat:@"%@.\"Z_PK\" = %@.%@",alias,joinAlias,quoted([join objectForKey:@"destinationColumn"])]];
     }
     else {
      /* The foreign key lives on the destination's row. */
      NSRelationshipDescription *inverse=[relationship inverseRelationship];

      [from addObject:[NSString stringWithFormat:@"%@ %@",quoted(tableNameForEntity(destination)),alias]];
      [where addObject:[NSString stringWithFormat:@"%@.%@ = %@.\"Z_PK\"",alias,quoted(columnNameForProperty([inverse name])),currentRef]];
     }
    }

    current=destination;
    currentRef=alias;
    index++;
   }

   if(lastEntity!=NULL)
    *lastEntity=current;

   return currentRef;
}

/* The SQL for comparing one column against the predicate's constant.  The
   column is named by the caller, which is what lets the same code serve a
   local attribute and one reached across a relationship (where it belongs
   to a table inside an EXISTS subquery). */
-(NSString *)_clauseForColumn:(NSString *)column
                    attribute:(NSAttributeDescription *)attribute
                     operator:(NSPredicateOperatorType)operator
              caseInsensitive:(BOOL)caseInsensitive
                     constant:(id)constant
                rhsExpression:(NSExpression *)rhs
                     bindings:(NSMutableArray *)bindings {
   /* "is it set" is exact for every type, whatever the column holds, and
      needs no value to compare against. */
   if(constant==nil && (operator==NSEqualToPredicateOperatorType || operator==NSNotEqualToPredicateOperatorType))
    return [NSString stringWithFormat:@"%@ IS %@NULL",column,(operator==NSEqualToPredicateOperatorType)?@"":@"NOT "];

   /* Equality admits more types than ordering does. */
   switch(operator){
    case NSEqualToPredicateOperatorType:
    case NSNotEqualToPredicateOperatorType:
    case NSInPredicateOperatorType:
     if(!attributeEqualityIsExactInSQL(attribute))
      return nil;
     break;
    default:
     if(!attributeComparesExactlyInSQL(attribute))
      return nil;
     break;
   }

   /* String matching applies to text columns only. */
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

   /* There is no per-comparison COLLATE NOCASE here; case-insensitive
      equality is expressed by folding both sides. */
   BOOL folded=(caseInsensitive && [attribute attributeType]==NSStringAttributeType);

   if(caseInsensitive && !folded)
    return nil;

   NSString *comparand=folded?[NSString stringWithFormat:@"LOWER(%@)",column]:column;

   switch(operator){

    case NSEqualToPredicateOperatorType: {

     NSString *placeholder=placeholderForBinding(bindings,attribute,constant);

     return [NSString stringWithFormat:@"%@ = %@",comparand,folded?[NSString stringWithFormat:@"LOWER(%@)",placeholder]:placeholder];
    }

    case NSNotEqualToPredicateOperatorType: {
     /* NULL rows do not match a != constant comparison (SQL NULL
        semantics), as in Apple's SQLite store. */
     NSString *placeholder=placeholderForBinding(bindings,attribute,constant);

     return [NSString stringWithFormat:@"%@ <> %@",comparand,folded?[NSString stringWithFormat:@"LOWER(%@)",placeholder]:placeholder];
    }

    case NSLessThanPredicateOperatorType:
    case NSLessThanOrEqualToPredicateOperatorType:
    case NSGreaterThanPredicateOperatorType:
    case NSGreaterThanOrEqualToPredicateOperatorType: {
     if(constant==nil || caseInsensitive)
      return nil;

     NSString *operatorSQL=(operator==NSLessThanPredicateOperatorType)?@"<":
                           (operator==NSLessThanOrEqualToPredicateOperatorType)?@"<=":
                           (operator==NSGreaterThanPredicateOperatorType)?@">":@">=";
     NSString *placeholder=placeholderForBinding(bindings,attribute,constant);

     return [NSString stringWithFormat:@"%@ %@ %@",[self codePointOrderedColumn:column isText:([attribute attributeType]==NSStringAttributeType)],operatorSQL,placeholder];
    }

    case NSInPredicateOperatorType: {
     if(caseInsensitive)
      return nil;

     NSArray *elements=constantCollectionFromExpression(rhs);

     if(elements==nil)
      return nil;

     NSUInteger count=[elements count];

     if(count==0)
      return @"FALSE";
     if(count>CDSQLStoreMaxInListSize)
      return nil;

     NSMutableArray *placeholders=[NSMutableArray array];

     for(id element in elements)
      [placeholders addObject:placeholderForBinding(bindings,attribute,element)];

     return [NSString stringWithFormat:@"%@ IN (%@)",column,[placeholders componentsJoinedByString:@", "]];
    }

    case NSBetweenPredicateOperatorType: {
     if(caseInsensitive)
      return nil;

     NSArray *elements=constantCollectionFromExpression(rhs);

     if([elements count]!=2)
      return nil;

     NSString *lower=placeholderForBinding(bindings,attribute,[elements objectAtIndex:0]);
     NSString *upper=placeholderForBinding(bindings,attribute,[elements objectAtIndex:1]);

     return [NSString stringWithFormat:@"%@ BETWEEN %@ AND %@",[self codePointOrderedColumn:column isText:([attribute attributeType]==NSStringAttributeType)],lower,upper];
    }

    case NSBeginsWithPredicateOperatorType:
     return [self _patternMatchClauseForColumn:column constant:constant caseInsensitive:caseInsensitive prefix:@"" suffix:@"%" bindings:bindings attribute:attribute];

    case NSEndsWithPredicateOperatorType:
     return [self _patternMatchClauseForColumn:column constant:constant caseInsensitive:caseInsensitive prefix:@"%" suffix:@"" bindings:bindings attribute:attribute];

    case NSContainsPredicateOperatorType:
     return [self _patternMatchClauseForColumn:column constant:constant caseInsensitive:caseInsensitive prefix:@"%" suffix:@"%" bindings:bindings attribute:attribute];

    case NSLikePredicateOperatorType: {
     /* NSPredicate LIKE wildcards: * (any sequence) and ? (any single
        character); SQL's are % and _. */
     NSMutableString *pattern=[NSMutableString stringWithString:escapedLikePattern(constant)];

     [pattern replaceOccurrencesOfString:@"*" withString:@"%" options:0 range:NSMakeRange(0,[pattern length])];
     [pattern replaceOccurrencesOfString:@"?" withString:@"_" options:0 range:NSMakeRange(0,[pattern length])];

     NSString *placeholder=placeholderForBinding(bindings,attribute,pattern);

     return caseInsensitive
         ?[self caseInsensitiveLikeClauseForColumn:column placeholder:placeholder]
         :[self caseSensitiveLikeClauseForColumn:column placeholder:placeholder];
    }

    default:
     return nil;
   }
}

/* ------------------------------------------------------------------ */
#pragma mark - Counting a relationship
/* ------------------------------------------------------------------ */

/* "how many related rows are there" is a question SQL answers directly, as
   a correlated COUNT.  Two spellings reach here:
 
     employees.@count > 2
     SUBQUERY(employees, $e, $e.age > 40).@count > 0
 
   The first is a key path ending in @count; the second is a function
   expression over a subquery, and only Apple's Foundation can build one -
   gnustep-base cannot parse SUBQUERY at all - so that half is written
   defensively and simply does not fire where the framework cannot produce
   it. */

/* The key path an expression names relative to a subquery's variable, or
   nil: $e.age is a valueForKeyPath: function over the variable. */
-(NSString *)_keyPathOfExpression:(NSExpression *)expression forVariable:(NSString *)variable {
   if([expression expressionType]==NSKeyPathExpressionType){
    NSString *keyPath=[expression keyPath];

    /* Some frameworks flatten $e.age into the key path "e.age". */
    if(variable!=nil && [keyPath hasPrefix:[variable stringByAppendingString:@"."]])
     return [keyPath substringFromIndex:[variable length]+1];

    return (variable==nil)?keyPath:nil;
   }

   if([expression expressionType]!=NSFunctionExpressionType)
    return nil;

   NSString     *keyPath=nil;
   NSExpression *operand=nil;
   NSArray      *arguments=nil;

   @try {
    if(![[expression function] isEqualToString:@"valueForKeyPath:"])
     return nil;
    operand=[expression operand];
    arguments=[expression arguments];
   } @catch(NSException *exception){
    return nil;
   }

   if(operand==nil || [operand expressionType]!=NSVariableExpressionType || [arguments count]!=1)
    return nil;
   if(variable!=nil && ![[operand variable] isEqualToString:variable])
    return nil;

   NSExpression *argument=[arguments objectAtIndex:0];

   @try {
    keyPath=([argument expressionType]==NSKeyPathExpressionType)?[argument keyPath]:[argument description];
   } @catch(NSException *exception){
    return nil;
   }

   return keyPath;
}

/* The predicate inside SUBQUERY(...), against the row the subquery walks:
   its columns belong to `alias`, and its key paths are written $e.<name>. */
-(NSString *)_translateSubqueryPredicate:(NSPredicate *)predicate
                                variable:(NSString *)variable
                                  entity:(NSEntityDescription *)entity
                                   alias:(NSString *)alias
                                bindings:(NSMutableArray *)bindings {
   if([predicate isKindOfClass:[NSCompoundPredicate class]]){
    NSCompoundPredicate *compound=(NSCompoundPredicate *)predicate;
    NSMutableArray      *clauses=[NSMutableArray array];

    for(NSPredicate *subpredicate in [compound subpredicates]){
     NSString *clause=[self _translateSubqueryPredicate:subpredicate variable:variable entity:entity alias:alias bindings:bindings];

     if(clause==nil)
      return nil;

     [clauses addObject:clause];
    }

    switch([compound compoundPredicateType]){
     case NSNotPredicateType:
      return ([clauses count]==1)?[NSString stringWithFormat:@"NOT (%@)",[clauses objectAtIndex:0]]:nil;
     case NSAndPredicateType:
      return [NSString stringWithFormat:@"(%@)",[clauses componentsJoinedByString:@" AND "]];
     case NSOrPredicateType:
      return [NSString stringWithFormat:@"(%@)",[clauses componentsJoinedByString:@" OR "]];
     default:
      return nil;
    }
   }

   if(![predicate isKindOfClass:[NSComparisonPredicate class]])
    return nil;

   NSComparisonPredicate *comparison=(NSComparisonPredicate *)predicate;

   if([comparison comparisonPredicateModifier]!=NSDirectPredicateModifier)
    return nil;

   NSComparisonPredicateOptions options=[comparison options];

   if((options&~NSCaseInsensitivePredicateOption)!=0)
    return nil;

   NSString     *keyPath=[self _keyPathOfExpression:[comparison leftExpression] forVariable:variable];
   NSExpression *rhs=[comparison rightExpression];

   if(keyPath==nil || [keyPath rangeOfString:@"."].location!=NSNotFound)
    return nil;   /* one hop inside the subquery; anything deeper is left alone */

   NSPropertyDescription *property=[propertiesForEntityChain(entity) objectForKey:keyPath];

   if(![property isKindOfClass:[NSAttributeDescription class]])
    return nil;

   BOOL rhsIsCollection=([comparison predicateOperatorType]==NSInPredicateOperatorType ||
                         [comparison predicateOperatorType]==NSBetweenPredicateOperatorType);
   id   constant=rhsIsCollection?nil:resolvedConstantValue([rhs constantValue]);

   if(!rhsIsCollection && [rhs expressionType]!=NSConstantValueExpressionType)
    return nil;
   if(constant==[NSNull null])
    constant=nil;

   return [self _clauseForColumn:[NSString stringWithFormat:@"%@.%@",alias,quoted(columnNameForProperty(keyPath))]
                       attribute:(NSAttributeDescription *)property
                        operator:[comparison predicateOperatorType]
                 caseInsensitive:((options&NSCaseInsensitivePredicateOption)!=0)
                        constant:constant
                   rhsExpression:rhs
                        bindings:bindings];
}

/* (SELECT COUNT(*) FROM <the rows the key path reaches> WHERE <they belong
   to this row> [AND <the subquery's own predicate>]) */
-(NSString *)_countSubqueryForKeyPath:(NSString *)keyPath
                               entity:(NSEntityDescription *)entity
                             variable:(NSString *)variable
                       innerPredicate:(NSPredicate *)innerPredicate
                             bindings:(NSMutableArray *)bindings {
   NSArray *segments=[keyPath componentsSeparatedByString:@"."];

   if([segments count]==0)
    return nil;

   NSMutableArray      *from=[NSMutableArray array];
   NSMutableArray      *where=[NSMutableArray array];
   NSEntityDescription *leafEntity=nil;
   NSString            *alias=[self _joinChainForSegments:segments
                                                   entity:entity
                                               outerTable:CDSQLOuterAlias
                                                   prefix:@"c"
                                                     from:from
                                                    where:where
                                               lastEntity:&leafEntity
                                            crossedToMany:NULL];

   if(alias==nil)
    return nil;

   if(innerPredicate!=nil){
    NSString *clause=[self _translateSubqueryPredicate:innerPredicate variable:variable entity:leafEntity alias:alias bindings:bindings];

    if(clause==nil)
     return nil;

    [where addObject:clause];
   }

   return [NSString stringWithFormat:@"(SELECT COUNT(*) FROM %@ WHERE %@)",
                                     [from componentsJoinedByString:@", "],
                                     [where componentsJoinedByString:@" AND "]];
}

/* The left-hand side of a comparison, when it counts a relationship: the
   key path walked, and the subquery's variable and predicate when it came
   from SUBQUERY(...).  Answers NO when this is not a count at all. */
-(BOOL)_countedKeyPathOfExpression:(NSExpression *)expression
                           keyPath:(NSString **)keyPath
                          variable:(NSString **)variable
                         predicate:(NSPredicate **)predicate {
   *keyPath=nil; *variable=nil; *predicate=nil;

   if([expression expressionType]==NSKeyPathExpressionType){
    NSString *path=[expression keyPath];

    if(![path hasSuffix:@".@count"])
     return NO;

    *keyPath=[path substringToIndex:[path length]-[@".@count" length]];

    return YES;
   }

   if([expression expressionType]!=NSFunctionExpressionType)
    return NO;

   @try {
    if(![[expression function] isEqualToString:@"valueForKeyPath:"])
     return NO;

    NSArray *arguments=[expression arguments];

    if([arguments count]!=1 || ![[[arguments objectAtIndex:0] description] isEqualToString:@"@count"])
     return NO;

    NSExpression *operand=[expression operand];

    if(operand==nil || [operand expressionType]!=NSSubqueryExpressionType)
     return NO;

    NSExpression *collection=[operand collection];

    if([collection expressionType]!=NSKeyPathExpressionType)
     return NO;

    *keyPath=[collection keyPath];
    *variable=[operand variable];
    *predicate=[operand predicate];
   } @catch(NSException *exception){
    return NO;   /* a framework that does not publish these parts */
   }

   return (*keyPath!=nil);
}

-(NSString *)_translateComparisonPredicate:(NSComparisonPredicate *)comparison entity:(NSEntityDescription *)entity bindings:(NSMutableArray *)bindings {
   NSComparisonPredicateModifier modifier=[comparison comparisonPredicateModifier];

   if(modifier!=NSDirectPredicateModifier &&
      modifier!=NSAnyPredicateModifier &&
      modifier!=NSAllPredicateModifier)
    return nil;

   NSComparisonPredicateOptions options=[comparison options];

   /* Only exact and [c] matches translate exactly; diacritic- or
      locale-sensitive matching happens in memory. */
   if((options&~NSCaseInsensitivePredicateOption)!=0)
    return nil;

   BOOL caseInsensitive=(options&NSCaseInsensitivePredicateOption)!=0;

   NSExpression           *lhs=[comparison leftExpression];
   NSExpression           *rhs=[comparison rightExpression];
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

   /* SELF == <object> / SELF IN <objects>: the row's own primary key.
      -[NSBatchDeleteRequest initWithObjectIDs:] exposes its ID list as
      exactly this predicate on its fetch request, so translating it here is
      what lets an ID-based batch delete work without reaching for the
      framework's private accessor.  An ID this store cannot resolve (a
      temporary one, or one belonging to another store) matches no row, so
      it is dropped from the list rather than making the whole predicate
      untranslatable. */
   /* A count of related rows, compared against a number. */
   {
    NSString    *countedKeyPath=nil;
    NSString    *countVariable=nil;
    NSPredicate *countPredicate=nil;

    if([self _countedKeyPathOfExpression:lhs keyPath:&countedKeyPath variable:&countVariable predicate:&countPredicate]){
     id count=resolvedConstantValue([rhs constantValue]);

     if([rhs expressionType]!=NSConstantValueExpressionType || ![count isKindOfClass:[NSNumber class]])
      return nil;

     NSString *operatorSQL=nil;

     switch(operator){
      case NSEqualToPredicateOperatorType:              operatorSQL=@"="; break;
      case NSNotEqualToPredicateOperatorType:           operatorSQL=@"<>"; break;
      case NSLessThanPredicateOperatorType:             operatorSQL=@"<"; break;
      case NSLessThanOrEqualToPredicateOperatorType:    operatorSQL=@"<="; break;
      case NSGreaterThanPredicateOperatorType:          operatorSQL=@">"; break;
      case NSGreaterThanOrEqualToPredicateOperatorType: operatorSQL=@">="; break;
      default:                                          return nil;
     }

     NSUInteger  mark=[bindings count];
     NSString   *subquery=[self _countSubqueryForKeyPath:countedKeyPath entity:entity variable:countVariable innerPredicate:countPredicate bindings:bindings];

     if(subquery==nil){
      while([bindings count]>mark)
       [bindings removeLastObject];
      return nil;
     }

     /* The count is a number of this store's own making, not user text. */
     return [NSString stringWithFormat:@"%@ %@ %lld",subquery,operatorSQL,[count longLongValue]];
    }
   }

   if(expressionIsSelf(lhs)){
    NSMutableArray *keys=[NSMutableArray array];

    if(operator==NSInPredicateOperatorType){
     NSArray *elements=constantCollectionFromExpression(rhs);

     if(elements==nil)
      return nil;

     for(id element in elements){
      NSNumber *primaryKey=[self _primaryKeyForRelationshipConstant:element];

      if(primaryKey!=nil)
       [keys addObject:[primaryKey description]];
     }
    }
    else if(operator==NSEqualToPredicateOperatorType || operator==NSNotEqualToPredicateOperatorType){
     NSNumber *primaryKey=[self _primaryKeyForRelationshipConstant:resolvedConstantValue([rhs constantValue])];

     if(primaryKey!=nil)
      [keys addObject:[primaryKey description]];
    }
    else
     return nil;

    BOOL negated=(operator==NSNotEqualToPredicateOperatorType);

    if([keys count]==0)
     return negated?@"TRUE":@"FALSE";
    if([keys count]>CDSQLStoreMaxInListSize)
     return nil;

    /* The list holds primary keys this store handed out, not user text. */
    return [NSString stringWithFormat:@"%@.\"Z_PK\" %@ (%@)",CDSQLOuterAlias,negated?@"NOT IN":@"IN",[keys componentsJoinedByString:@", "]];
   }

   if([lhs expressionType]!=NSKeyPathExpressionType)
    return nil;

   BOOL rhsIsCollection=(operator==NSInPredicateOperatorType || operator==NSBetweenPredicateOperatorType);

   if(!rhsIsCollection && [rhs expressionType]!=NSConstantValueExpressionType)
    return nil;

   NSString *keyPath=[lhs keyPath];
   id        constant=rhsIsCollection?nil:resolvedConstantValue([rhs constantValue]);

   if(constant==[NSNull null])
    constant=nil;
   if([constant isKindOfClass:[NSExpression class]])
    return nil;

   /* A key path that crosses relationships becomes an EXISTS subquery over
      the tables it walks through. */
   if([keyPath rangeOfString:@"."].location!=NSNotFound){
    NSArray             *segments=[keyPath componentsSeparatedByString:@"."];
    NSMutableArray      *from=[NSMutableArray array];
    NSMutableArray      *where=[NSMutableArray array];
    NSEntityDescription *leafEntity=nil;
    BOOL                 crossedToMany=NO;
    NSString            *alias=[self _joinChainForSegments:[segments subarrayWithRange:NSMakeRange(0,[segments count]-1)]
                                                    entity:entity
                                                outerTable:CDSQLOuterAlias
                                                    prefix:@"j"
                                                      from:from
                                                     where:where
                                                lastEntity:&leafEntity
                                             crossedToMany:&crossedToMany];

    if(alias==nil)
     return nil;

    /* ANY/ALL say what a to-many crossing means; without one, a path
       through a to-many has no single answer, so it is left to the
       in-memory fallback. */
    if(crossedToMany && modifier==NSDirectPredicateModifier)
     return nil;
    if(!crossedToMany && modifier!=NSDirectPredicateModifier)
     return nil;

    NSPropertyDescription *leaf=[propertiesForEntityChain(leafEntity) objectForKey:[segments lastObject]];

    if(![leaf isKindOfClass:[NSAttributeDescription class]])
     return nil;

    NSString *clause=[self _clauseForColumn:[NSString stringWithFormat:@"%@.%@",alias,quoted(columnNameForProperty([segments lastObject]))]
                                  attribute:(NSAttributeDescription *)leaf
                                   operator:operator
                            caseInsensitive:caseInsensitive
                                   constant:constant
                              rhsExpression:rhs
                                   bindings:bindings];

    if(clause==nil)
     return nil;

    /* ALL is "none fails it", which has to be written so that a NULL
       comparison counts as a failure rather than as unknown. */
    if(modifier==NSAllPredicateModifier)
     [where addObject:[NSString stringWithFormat:@"(%@) IS NOT TRUE",clause]];
    else
     [where addObject:clause];

    return [NSString stringWithFormat:@"%@EXISTS (SELECT 1 FROM %@ WHERE %@)",
                                      (modifier==NSAllPredicateModifier)?@"NOT ":@"",
                                      [from componentsJoinedByString:@", "],
                                      [where componentsJoinedByString:@" AND "]];
   }

   if(modifier!=NSDirectPredicateModifier)
    return nil;

   NSPropertyDescription *property=[propertiesForEntityChain(entity) objectForKey:keyPath];

   NSString *column=[NSString stringWithFormat:@"%@.%@",CDSQLOuterAlias,quoted(columnNameForProperty(keyPath))];

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

    NSString *placeholder=placeholderForBinding(bindings,relationship,primaryKey);

    return [NSString stringWithFormat:@"%@ %@ %@",column,(operator==NSEqualToPredicateOperatorType)?@"=":@"<>",placeholder];
   }

   if(![property isKindOfClass:[NSAttributeDescription class]])
    return nil;

   return [self _clauseForColumn:column
                       attribute:(NSAttributeDescription *)property
                        operator:operator
                 caseInsensitive:caseInsensitive
                        constant:constant
                   rhsExpression:rhs
                        bindings:bindings];
}

/* Translates what can be translated, and hands back the rest.
 
   The interesting case is AND: a predicate like "name == 'Ada' AND picture
   != nil" used to translate as nothing at all, because one conjunct could
   not be expressed in SQL - so the fetch read every row of the table and
   filtered in memory.  Each conjunct is now translated on its own, the ones
   that succeed go into the WHERE clause, and only the remainder is
   evaluated in memory, over the rows that survived it.
 
   OR and NOT cannot be split that way: dropping a disjunct would narrow the
   result, and dropping part of a negation would widen it.  Either the whole
   thing translates or none of it does.
 
   `residual` is the part that did not translate, and nil when everything
   did. */
-(NSString *)_translatePredicate:(NSPredicate *)predicate
                          entity:(NSEntityDescription *)entity
                        bindings:(NSMutableArray *)bindings
                        residual:(NSPredicate **)residual {
   if(residual!=NULL)
    *residual=nil;

   if([predicate isKindOfClass:[NSCompoundPredicate class]]){
    NSCompoundPredicate *compound=(NSCompoundPredicate *)predicate;
    NSArray             *subpredicates=[compound subpredicates];

    if([compound compoundPredicateType]==NSAndPredicateType){
     NSMutableArray *clauses=[NSMutableArray array];
     NSMutableArray *residuals=[NSMutableArray array];

     for(NSPredicate *subpredicate in subpredicates){
      NSUInteger   mark=[bindings count];
      NSPredicate *subresidual=nil;
      NSString    *clause=[self _translatePredicate:subpredicate entity:entity bindings:bindings residual:&subresidual];

      if(clause!=nil)
       [clauses addObject:clause];
      if(subresidual!=nil){
       /* A conjunct that translated only in part contributes its
          translated half to the clause and its remainder here; one that
          translated not at all leaves no bindings behind. */
       if(clause==nil)
        while([bindings count]>mark)
         [bindings removeLastObject];
       [residuals addObject:subresidual];
      }
     }

     if([residuals count]>0 && residual!=NULL)
      *residual=([residuals count]==1)
          ?[residuals objectAtIndex:0]
          :[NSCompoundPredicate andPredicateWithSubpredicates:residuals];

     if([clauses count]==0)
      return nil;

     return [NSString stringWithFormat:@"(%@)",[clauses componentsJoinedByString:@" AND "]];
    }

    /* OR and NOT: all of it, or none of it. */
    NSUInteger      mark=[bindings count];
    NSMutableArray *clauses=[NSMutableArray array];

    for(NSPredicate *subpredicate in subpredicates){
     NSPredicate *subresidual=nil;
     NSString    *clause=[self _translatePredicate:subpredicate entity:entity bindings:bindings residual:&subresidual];

     if(clause==nil || subresidual!=nil){
      while([bindings count]>mark)
       [bindings removeLastObject];
      if(residual!=NULL)
       *residual=predicate;
      return nil;
     }

     [clauses addObject:clause];
    }

    switch([compound compoundPredicateType]){
     case NSNotPredicateType:
      if([clauses count]!=1){
       if(residual!=NULL)
        *residual=predicate;
       return nil;
      }
      return [NSString stringWithFormat:@"NOT (%@)",[clauses objectAtIndex:0]];
     case NSOrPredicateType:
      if([clauses count]==0)
       return @"FALSE";
      return [NSString stringWithFormat:@"(%@)",[clauses componentsJoinedByString:@" OR "]];
     default:
      if(residual!=NULL)
       *residual=predicate;
      return nil;
    }
   }

   if([predicate isKindOfClass:[NSComparisonPredicate class]]){
    NSUInteger  mark=[bindings count];
    NSString   *clause=[self _translateComparisonPredicate:(NSComparisonPredicate *)predicate entity:entity bindings:bindings];

    if(clause==nil){
     while([bindings count]>mark)
      [bindings removeLastObject];
     if(residual!=NULL)
      *residual=predicate;
    }

    return clause;
   }

   if([predicate isEqual:[NSPredicate predicateWithValue:YES]])
    return @"TRUE";
   if([predicate isEqual:[NSPredicate predicateWithValue:NO]])
    return @"FALSE";

   if(residual!=NULL)
    *residual=predicate;

   return nil;
}

/* The all-or-nothing form, for callers that cannot use a residual. */
-(NSString *)_translatePredicate:(NSPredicate *)predicate entity:(NSEntityDescription *)entity bindings:(NSMutableArray *)bindings {
   NSUInteger   mark=[bindings count];
   NSPredicate *residual=nil;
   NSString    *clause=[self _translatePredicate:predicate entity:entity bindings:bindings residual:&residual];

   if(residual==nil)
    return clause;

   while([bindings count]>mark)
    [bindings removeLastObject];

   return nil;
}

/* ORDER BY terms, and the joins they need.
 
   A sort key that lives in another table - "employer.name" - is reached by
   joining that table in, LEFT so that a row with no related row still
   sorts (as it does in memory, where the missing value is nil).  Only
   to-one hops can be joined this way: "employees.name" has no single value
   to sort by, and Core Data does not define one, so it is left to the
   in-memory sort.
 
   Answers nil when a descriptor cannot be expressed, in which case the
   caller sorts in memory. */
-(NSString *)_translateSortDescriptors:(NSArray *)sortDescriptors
                                entity:(NSEntityDescription *)entity
                                 joins:(NSMutableArray *)joins
                              joinedBy:(NSMutableDictionary *)aliasesByKeyPath {
   NSMutableArray *terms=[NSMutableArray array];

   for(NSSortDescriptor *descriptor in sortDescriptors){
    NSString *key=[descriptor key];

    if(key==nil)
     return nil;

    NSEntityDescription *leafEntity=entity;
    NSString            *qualifier=CDSQLOuterAlias;
    NSString            *leafKey=key;

    if([key rangeOfString:@"."].location!=NSNotFound){
     NSArray  *segments=[key componentsSeparatedByString:@"."];
     NSString *walked=nil;

     leafKey=[segments lastObject];

     /* One LEFT JOIN per hop, reused when two descriptors walk the same
        path. */
     for(NSUInteger i=0;i+1<[segments count];i++){
      NSString                  *segment=[segments objectAtIndex:i];
      NSRelationshipDescription *relationship=[propertiesForEntityChain(leafEntity) objectForKey:segment];

      if(![relationship isKindOfClass:[NSRelationshipDescription class]] || [relationship isToMany])
       return nil;

      walked=(walked==nil)?segment:[walked stringByAppendingFormat:@".%@",segment];

      NSString *existing=[aliasesByKeyPath objectForKey:walked];

      if(existing==nil){
       NSString *alias=[NSString stringWithFormat:@"s%lu",(unsigned long)[aliasesByKeyPath count]];

       [joins addObject:[NSString stringWithFormat:@"LEFT JOIN %@ %@ ON %@.\"Z_PK\" = %@.%@",
                                                   quoted(tableNameForEntity([relationship destinationEntity])),alias,
                                                   alias,qualifier,quoted(columnNameForProperty(segment))]];
       [aliasesByKeyPath setObject:alias forKey:walked];
       existing=alias;
      }

      qualifier=existing;
      leafEntity=[relationship destinationEntity];
     }
    }

    NSPropertyDescription *property=[propertiesForEntityChain(leafEntity) objectForKey:leafKey];

    if(![property isKindOfClass:[NSAttributeDescription class]] || !attributeComparesExactlyInSQL((NSAttributeDescription *)property))
     return nil;

    SEL       selector=[descriptor selector];
    NSString *selectorName=(selector!=NULL)?NSStringFromSelector(selector):nil;
    NSString *term=[NSString stringWithFormat:@"%@.%@",qualifier,quoted(columnNameForProperty(leafKey))];

    if(selectorName!=nil && [selectorName isEqualToString:@"caseInsensitiveCompare:"]){
     if([(NSAttributeDescription *)property attributeType]!=NSStringAttributeType)
      return nil;
     term=[NSString stringWithFormat:@"LOWER(%@)",term];
    }
    else if(selectorName!=nil && ![selectorName isEqualToString:@"compare:"])
     return nil;

    /* Both orderings are code-point orderings, as NSString's are. */
    term=[self codePointOrderedColumn:term isText:([(NSAttributeDescription *)property attributeType]==NSStringAttributeType)];

    [terms addObject:[NSString stringWithFormat:@"%@ %@",term,[descriptor ascending]?@"ASC":@"DESC"]];
   }

   return [terms componentsJoinedByString:@", "];
}

/* ------------------------------------------------------------------ */
#pragma mark - Projections and aggregates
/* ------------------------------------------------------------------ */

/* An NSExpressionDescription asks for something computed: max:, sum: and
   friends over a key path.  Answers the SQL, or nil when this is not a
   shape the store can express. */
-(NSString *)_aggregateSQLForExpressionDescription:(NSExpressionDescription *)description entity:(NSEntityDescription *)entity {
   return [self _aggregateSQLForExpression:[description expression] entity:entity];
}

-(NSString *)_aggregateSQLForExpression:(NSExpression *)expression entity:(NSEntityDescription *)entity {
   if([expression expressionType]!=NSFunctionExpressionType)
    return nil;

   NSString *function=nil;
   NSArray  *arguments=nil;

   @try {
    function=[expression function];
    arguments=[expression arguments];
   } @catch(NSException *exception){
    return nil;
   }

   NSDictionary *aggregates=[NSDictionary dictionaryWithObjectsAndKeys:
       @"COUNT",@"count:",
       @"SUM",@"sum:",
       @"MIN",@"min:",
       @"MAX",@"max:",
       @"AVG",@"average:",
       nil];
   NSString     *aggregate=[aggregates objectForKey:function];

   if(aggregate==nil || [arguments count]!=1)
    return nil;

   NSExpression *argument=[arguments objectAtIndex:0];

   if([argument expressionType]!=NSKeyPathExpressionType)
    return nil;

   NSString *keyPath=[argument keyPath];

   if([keyPath rangeOfString:@"."].location!=NSNotFound)
    return nil;   /* an aggregate over another table would need its join */

   NSPropertyDescription *property=[propertiesForEntityChain(entity) objectForKey:keyPath];

   if(![property isKindOfClass:[NSAttributeDescription class]])
    return nil;

   return [NSString stringWithFormat:@"%@(%@.%@)",aggregate,CDSQLOuterAlias,quoted(columnNameForProperty(keyPath))];
}

/* A predicate over the select list rather than over columns: a HAVING
   clause names the things the query selects - a grouped attribute, or an
   aggregate by the name its expression description carries - so each key
   path is looked up there. */
-(NSString *)_translateProjectedPredicate:(NSPredicate *)predicate
                              expressions:(NSDictionary *)expressionsByName
                                   entity:(NSEntityDescription *)entity
                                 bindings:(NSMutableArray *)bindings {
   if([predicate isKindOfClass:[NSCompoundPredicate class]]){
    NSCompoundPredicate *compound=(NSCompoundPredicate *)predicate;
    NSMutableArray      *clauses=[NSMutableArray array];

    for(NSPredicate *subpredicate in [compound subpredicates]){
     NSString *clause=[self _translateProjectedPredicate:subpredicate expressions:expressionsByName entity:entity bindings:bindings];

     if(clause==nil)
      return nil;

     [clauses addObject:clause];
    }

    switch([compound compoundPredicateType]){
     case NSNotPredicateType:
      return ([clauses count]==1)?[NSString stringWithFormat:@"NOT (%@)",[clauses objectAtIndex:0]]:nil;
     case NSAndPredicateType:
      return [NSString stringWithFormat:@"(%@)",[clauses componentsJoinedByString:@" AND "]];
     case NSOrPredicateType:
      return [NSString stringWithFormat:@"(%@)",[clauses componentsJoinedByString:@" OR "]];
     default:
      return nil;
    }
   }

   if(![predicate isKindOfClass:[NSComparisonPredicate class]])
    return nil;

   NSComparisonPredicate *comparison=(NSComparisonPredicate *)predicate;
   NSExpression          *lhs=[comparison leftExpression];
   NSExpression          *rhs=[comparison rightExpression];

   if([comparison comparisonPredicateModifier]!=NSDirectPredicateModifier)
    return nil;
   if([rhs expressionType]!=NSConstantValueExpressionType)
    return nil;

   /* Either spelling: the name the request gave a selected expression, or
      the aggregate written out - count:(name) > 1, which is the form
      Apple's own documentation uses and the one this framework's in-memory
      grouping expects. */
   NSString *expression=nil;

   if([lhs expressionType]==NSKeyPathExpressionType)
    expression=[expressionsByName objectForKey:[lhs keyPath]];
   else if([lhs expressionType]==NSFunctionExpressionType)
    expression=[self _aggregateSQLForExpression:lhs entity:entity];

   if(expression==nil)
    return nil;

   NSString *operatorSQL=nil;

   switch([comparison predicateOperatorType]){
    case NSEqualToPredicateOperatorType:              operatorSQL=@"="; break;
    case NSNotEqualToPredicateOperatorType:           operatorSQL=@"<>"; break;
    case NSLessThanPredicateOperatorType:             operatorSQL=@"<"; break;
    case NSLessThanOrEqualToPredicateOperatorType:    operatorSQL=@"<="; break;
    case NSGreaterThanPredicateOperatorType:          operatorSQL=@">"; break;
    case NSGreaterThanOrEqualToPredicateOperatorType: operatorSQL=@">="; break;
    default:                                          return nil;
   }

   id constant=resolvedConstantValue([rhs constantValue]);

   if([constant isKindOfClass:[NSNumber class]])
    return [NSString stringWithFormat:@"%@ %@ %@",expression,operatorSQL,[constant description]];

   if([constant isKindOfClass:[NSString class]]){
    [bindings addObject:constant];

    return [NSString stringWithFormat:@"%@ %@ $%lu",expression,operatorSQL,(unsigned long)[bindings count]];
   }

   return nil;
}

/* ORDER BY over the select list, which is what a grouped query can sort
   by: the grouped columns and the aggregates, under the names the request
   gave them. */
-(NSString *)_translateProjectedSortDescriptors:(NSArray *)sortDescriptors expressions:(NSDictionary *)expressionsByName {
   NSMutableArray *terms=[NSMutableArray array];

   for(NSSortDescriptor *descriptor in sortDescriptors){
    NSString *expression=[expressionsByName objectForKey:[descriptor key]];

    if(expression==nil)
     return nil;

    SEL       selector=[descriptor selector];
    NSString *selectorName=(selector!=NULL)?NSStringFromSelector(selector):nil;

    if(selectorName!=nil && ![selectorName isEqualToString:@"compare:"])
     return nil;

    [terms addObject:[NSString stringWithFormat:@"%@ %@",expression,[descriptor ascending]?@"ASC":@"DESC"]];
   }

   return [terms componentsJoinedByString:@", "];
}

/* The dictionary-shaped result, read as columns rather than objects.
 
   This is the one result type where materializing managed objects is pure
   waste: the caller asked for values.  Selecting the columns also makes
   DISTINCT, GROUP BY and aggregates the database's work rather than ours.
 
   Answers nil when the request is not one the store can project, and the
   caller falls back to reading the objects. */
-(CDSQLQuery *)_projectionQueryForRequest:(NSFetchRequest *)request
                                   entity:(NSEntityDescription *)entity
                                 whereSQL:(NSString *)whereSQL
                                 bindings:(NSArray *)bindings
                                    joins:(NSArray *)joins
                               orderBySQL:(NSString *)orderBySQL
                                    names:(NSMutableArray *)names {
   NSArray *fetchProperties=[request propertiesToFetch];

   if([fetchProperties count]==0)
    return nil;   /* "everything" still goes through the objects */

   CDSQLQuery          *query=[CDSQLQuery queryFromTable:quoted(tableNameForEntity(entity)) alias:CDSQLOuterAlias];
   NSMutableDictionary *expressionsByName=[NSMutableDictionary dictionary];

   for(id fetchProperty in fetchProperties){
    NSString *name=nil;
    NSString *expression=nil;

    if([fetchProperty isKindOfClass:[NSExpressionDescription class]]){
     name=[(NSExpressionDescription *)fetchProperty name];
     expression=[self _aggregateSQLForExpressionDescription:fetchProperty entity:entity];
    }
    else {
     name=[fetchProperty isKindOfClass:[NSString class]]?fetchProperty:[(NSPropertyDescription *)fetchProperty name];

     NSPropertyDescription *property=[propertiesForEntityChain(entity) objectForKey:name];

     if([property isKindOfClass:[NSAttributeDescription class]])
      expression=[NSString stringWithFormat:@"%@.%@",CDSQLOuterAlias,quoted(columnNameForProperty(name))];
    }

    if(name==nil || expression==nil)
     return nil;

    [query selectExpression:expression];
    [names addObject:name];
    [expressionsByName setObject:expression forKey:name];
   }

   for(NSString *join in joins)
    [query addJoin:join];

   [query addCondition:[NSString stringWithFormat:@"%@.\"Z_ENT\" IN (%@)",CDSQLOuterAlias,[self _entityIDListForEntity:entity includesSubentities:[request includesSubentities]]]];
   [query addCondition:(whereSQL!=nil)?[NSString stringWithFormat:@"(%@)",whereSQL]:nil];
   [[query parameters] addObjectsFromArray:bindings];

   BOOL grouped=([[request propertiesToGroupBy] count]>0);

   for(id groupedProperty in [request propertiesToGroupBy]){
    NSString              *name=[groupedProperty isKindOfClass:[NSString class]]?groupedProperty:[(NSPropertyDescription *)groupedProperty name];
    NSPropertyDescription *property=[propertiesForEntityChain(entity) objectForKey:name];

    if(![property isKindOfClass:[NSAttributeDescription class]])
     return nil;

    NSString *expression=[NSString stringWithFormat:@"%@.%@",CDSQLOuterAlias,quoted(columnNameForProperty(name))];

    /* A grouped column can be named in HAVING and in ORDER BY whether or
       not the request also selected it. */
    if([expressionsByName objectForKey:name]==nil)
     [expressionsByName setObject:expression forKey:name];

    [query addGroupBy:expression];
   }

   if([request havingPredicate]!=nil){
    NSString *having=[self _translateProjectedPredicate:[request havingPredicate] expressions:expressionsByName entity:entity bindings:[query parameters]];

    if(having==nil)
     return nil;

    [query setHaving:having];
   }

   [query setDistinct:[request returnsDistinctResults]];

   if([[request sortDescriptors] count]>0){
    /* A grouped query can only sort by what it selects; an ungrouped one
       may sort by any column, which is what orderBySQL already holds. */
    NSString *projectedOrder=[self _translateProjectedSortDescriptors:[request sortDescriptors] expressions:expressionsByName];

    if(projectedOrder!=nil)
     [query addOrderBy:projectedOrder];
    else if(!grouped && [orderBySQL length]>0)
     [query addOrderBy:orderBySQL];
    else
     return nil;
   }

   [query setLimit:[request fetchLimit] offset:[request fetchOffset]];

   return query;
}

-(NSArray *)_projectedRowsForRequest:(NSFetchRequest *)request
                              entity:(NSEntityDescription *)entity
                            whereSQL:(NSString *)whereSQL
                            bindings:(NSArray *)bindings
                               joins:(NSArray *)joins
                          orderBySQL:(NSString *)orderBySQL
                               error:(NSError **)error {
   NSMutableArray *names=[NSMutableArray array];
   CDSQLQuery     *query=[self _projectionQueryForRequest:request entity:entity whereSQL:whereSQL bindings:bindings joins:joins orderBySQL:orderBySQL names:names];

   if(query==nil)
    return nil;

   id<CDSQLResult> result=[self execute:[query SQL] parameters:[query parameters] error:error];

   if(result==nil)
    return nil;

   /* The values come back as the attributes they were selected from; an
      aggregate has no attribute, and is read as a number. */
   NSMutableArray *rows=[NSMutableArray array];
   NSUInteger      i,rowCount=[result rowCount];

   for(i=0;i<rowCount;i++){
    NSMutableDictionary *row=[NSMutableDictionary dictionary];
    NSUInteger           column;

    for(column=0;column<[names count];column++){
     NSString              *name=[names objectAtIndex:column];
     NSPropertyDescription *property=[propertiesForEntityChain(entity) objectForKey:name];
     id                     value=nil;

     if([result isNullAtRow:i column:column])
      continue;

     if([property isKindOfClass:[NSAttributeDescription class]])
      value=attributeValueFromResult(result,(int)i,(int)column,(NSAttributeDescription *)property);
     else {
      NSString *text=[result stringAtRow:i column:column];

      value=([text rangeOfString:@"."].location!=NSNotFound)
          ?(id)[NSNumber numberWithDouble:[text doubleValue]]
          :(id)[NSNumber numberWithLongLong:[text longLongValue]];
     }

     if(value!=nil)
      [row setObject:value forKey:name];
    }

    [rows addObject:row];
   }

   return rows;
}

/* Whether the rows are one per object, or fewer.  Used to refuse a
   request the store said it would shape and then could not, rather than
   quietly answering ungrouped rows. */
static BOOL requestReshapesRows(NSFetchRequest *request){
   if([[request propertiesToGroupBy] count]>0 || [request havingPredicate]!=nil)
    return YES;

   /* An aggregate collapses the rows; a plain expression description does
      not, and the older object-built path still answers those. */
   for(id fetchProperty in [request propertiesToFetch])
    if([fetchProperty isKindOfClass:[NSExpressionDescription class]] &&
       [[(NSExpressionDescription *)fetchProperty expression] expressionType]==NSFunctionExpressionType)
     return YES;

   return NO;
}

/* Answers whether this store can produce the dictionary rows itself.
 
   The framework asks this - by respondsToSelector:, so it is a courtesy,
   not a contract - before it decides to fetch every object and group them
   in memory.  A grouped request answered here is one statement; answered
   there it is the whole table.
 
   The answer is not a guess: it builds the very query the fetch would run
   and says yes if it came out.  What cannot be built - an aggregate over a
   relationship, a predicate that does not translate exactly, a sort on
   something the grouped query does not select - is left to the framework,
   which is still right, only slower. */
-(BOOL)_canShapeDictionaryRequest:(NSFetchRequest *)request {
   if([request resultType]!=NSDictionaryResultType)
    return NO;

   NSEntityDescription *entity=[self _entityForFetchRequest:request];

   if(entity==nil)
    return NO;

   NSMutableArray *bindings=[NSMutableArray array];
   NSString       *whereSQL=nil;
   NSPredicate    *residual=nil;

   if([request predicate]!=nil){
    whereSQL=[self _translatePredicate:[request predicate] entity:entity bindings:bindings residual:&residual];

    if(residual!=nil)
     return NO;   /* rows would be filtered after grouping, which is not the same result */
   }

   NSMutableArray      *sortJoins=[NSMutableArray array];
   NSMutableDictionary *sortAliases=[NSMutableDictionary dictionary];
   NSString            *orderBySQL=nil;

   if([[request sortDescriptors] count]>0){
    orderBySQL=[self _translateSortDescriptors:[request sortDescriptors] entity:entity joins:sortJoins joinedBy:sortAliases];

    if(orderBySQL==nil)
     [sortJoins removeAllObjects];
   }

   return [self _projectionQueryForRequest:request entity:entity whereSQL:whereSQL bindings:bindings joins:sortJoins orderBySQL:orderBySQL names:[NSMutableArray array]]!=nil;
}

/* ------------------------------------------------------------------ */
#pragma mark - Fetching
/* ------------------------------------------------------------------ */

/* The Z_ENT list of an entity and its subentities, as SQL literals. */
-(NSString *)_entityIDListForEntity:(NSEntityDescription *)entity includesSubentities:(BOOL)includesSubentities {
   NSMutableArray *entityIDs=[NSMutableArray array];

   if(includesSubentities)
    [self _collectEntityIDsOfEntity:entity into:entityIDs];
   else
    [entityIDs addObject:[NSNumber numberWithLongLong:[self _entityIDForEntity:entity]]];

   return [entityIDs componentsJoinedByString:@", "];
}

/* -1 on failure, so that a count of zero is not mistaken for one. */
-(long long)_countForEntity:(NSEntityDescription *)entity includesSubentities:(BOOL)includesSubentities whereSQL:(NSString *)whereSQL bindings:(NSArray *)bindings error:(NSError **)error {
   if([_entityIDs objectForKey:[entity name]]==nil)
    return 0;

   CDSQLQuery *query=[CDSQLQuery queryFromTable:quoted(tableNameForEntity(entity)) alias:CDSQLOuterAlias];

   [query selectExpression:@"COUNT(*)"];
   [query addCondition:[NSString stringWithFormat:@"%@.\"Z_ENT\" IN (%@)",CDSQLOuterAlias,[self _entityIDListForEntity:entity includesSubentities:includesSubentities]]];
   [query addCondition:(whereSQL!=nil)?[NSString stringWithFormat:@"(%@)",whereSQL]:nil];
   [[query parameters] addObjectsFromArray:bindings];

   id<CDSQLResult> result=[self execute:[query SQL] parameters:[query parameters] error:error];

   if(result==nil)
    return -1;

   return ([result rowCount]>0)?[result longLongAtRow:0 column:0]:0;
}

-(NSArray *)_fetchObjectIDsForEntity:(NSEntityDescription *)entity includesSubentities:(BOOL)includesSubentities whereSQL:(NSString *)whereSQL bindings:(NSArray *)bindings orderBySQL:(NSString *)orderBySQL joins:(NSArray *)joins fetchLimit:(NSUInteger)fetchLimit fetchOffset:(NSUInteger)fetchOffset error:(NSError **)error {
   if([_entityIDs objectForKey:[entity name]]==nil)
    return [NSArray array];

   CDSQLQuery *query=[CDSQLQuery queryFromTable:quoted(tableNameForEntity(entity)) alias:CDSQLOuterAlias];

   [query selectExpression:[NSString stringWithFormat:@"%@.\"Z_PK\"",CDSQLOuterAlias]];
   [query selectExpression:[NSString stringWithFormat:@"%@.\"Z_ENT\"",CDSQLOuterAlias]];

   for(NSString *join in joins)
    [query addJoin:join];

   /* The Z_ENT list holds one trusted integer literal per entity in the
      model subtree, so it is bounded by the model size. */
   [query addCondition:[NSString stringWithFormat:@"%@.\"Z_ENT\" IN (%@)",CDSQLOuterAlias,[self _entityIDListForEntity:entity includesSubentities:includesSubentities]]];
   [query addCondition:(whereSQL!=nil)?[NSString stringWithFormat:@"(%@)",whereSQL]:nil];
   [[query parameters] addObjectsFromArray:bindings];

   if([orderBySQL length]>0)
    [query addOrderBy:orderBySQL];
   [query addOrderBy:[NSString stringWithFormat:@"%@.\"Z_PK\"",CDSQLOuterAlias]];

   [query setLimit:fetchLimit offset:fetchOffset];

   NSString *sql=[query SQL];

   bindings=[query parameters];

   id<CDSQLResult> result=[self execute:sql parameters:bindings error:error];

   if(result==nil)
    return nil;

   NSMutableArray *objectIDs=[NSMutableArray array];
   int             i,count=(int)[result rowCount];

   for(i=0;i<count;i++){
    long long            primaryKey=[result longLongAtRow:i column:0];
    NSEntityDescription *rowEntity=[self _entityForEntityID:[result longLongAtRow:i column:1]];

    if(rowEntity==nil)
     rowEntity=entity;

    [objectIDs addObject:[[self newObjectIDForEntity:rowEntity referenceObject:referenceObjectForPrimaryKey(primaryKey)] autorelease]];
   }

   
   return objectIDs;
}

/* [request entity] is nil for a request built from an entity name alone. */
-(NSEntityDescription *)_entityForFetchRequest:(NSFetchRequest *)request {
   NSEntityDescription *entity=[request entity];

   if(entity!=nil)
    return entity;

   NSString *name=[request entityName];

   if(name==nil)
    return nil;

   return [[[[self persistentStoreCoordinator] managedObjectModel] entitiesByName] objectForKey:name];
}

-(id)_executeFetchRequest:(NSFetchRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSEntityDescription *entity=[self _entityForFetchRequest:request];

   if(entity==nil){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:@"fetch request without a resolvable entity" forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   /* Predicates and sort descriptors are translated to SQL when possible;
      anything that would not translate exactly is evaluated in memory, and
      the limit/offset can only be pushed down when nothing is. */
   NSMutableArray *bindings=[NSMutableArray array];
   NSString       *whereSQL=nil;
   NSPredicate    *residualPredicate=nil;

   if([request predicate]!=nil)
    whereSQL=[self _translatePredicate:[request predicate] entity:entity bindings:bindings residual:&residualPredicate];

   BOOL predicateInSQL=(residualPredicate==nil);

   BOOL countOnly=([request resultType]==NSCountResultType);

   NSString            *orderBySQL=nil;
   NSMutableArray      *sortJoins=[NSMutableArray array];
   NSMutableDictionary *sortAliases=[NSMutableDictionary dictionary];
   BOOL                 sortsInSQL=YES;

   if(!countOnly && [[request sortDescriptors] count]>0){
    orderBySQL=[self _translateSortDescriptors:[request sortDescriptors] entity:entity joins:sortJoins joinedBy:sortAliases];
    sortsInSQL=(orderBySQL!=nil);

    if(!sortsInSQL)
     [sortJoins removeAllObjects];
   }

   BOOL       filtersInMemory=(!predicateInSQL || !sortsInSQL);
   NSUInteger sqlLimit=filtersInMemory?0:[request fetchLimit];
   NSUInteger sqlOffset=filtersInMemory?0:[request fetchOffset];

   /* A count the database can answer is asked of it as a count: fetching
      every matching key only to take the length of the array reads the
      whole result set for a single number. */
   if(countOnly && predicateInSQL && [request fetchLimit]==0 && [request fetchOffset]==0){
    long long count=[self _countForEntity:entity includesSubentities:[request includesSubentities] whereSQL:whereSQL bindings:bindings error:error];

    if(count<0)
     return nil;

    return [NSArray arrayWithObject:[NSNumber numberWithUnsignedInteger:(NSUInteger)count]];
   }

   /* Values, not objects: read the columns and be done, when everything
      the request asks for can be expressed in the query. */
   if([request resultType]==NSDictionaryResultType && predicateInSQL){
    NSError *projectionError=nil;
    NSArray *rows=[self _projectedRowsForRequest:request entity:entity whereSQL:whereSQL bindings:bindings joins:sortJoins orderBySQL:orderBySQL error:&projectionError];

    if(rows!=nil)
     return rows;
    if(projectionError!=nil && error!=NULL)
     *error=projectionError;
    if(projectionError!=nil)
     return nil;
   }

   /* Below here rows are built from objects, one row each.  That is not an
      answer to a grouped or aggregated request, so say so instead of
      returning rows of the wrong shape. */
   if([request resultType]==NSDictionaryResultType && requestReshapesRows(request)){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:@"the store cannot express this grouped or aggregated fetch request" forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   NSArray *objectIDs=[self _fetchObjectIDsForEntity:entity includesSubentities:[request includesSubentities] whereSQL:whereSQL bindings:bindings orderBySQL:orderBySQL joins:sortJoins fetchLimit:sqlLimit fetchOffset:sqlOffset error:error];

   if(objectIDs==nil)
    return nil;

   if(countOnly && predicateInSQL)
    return [NSArray arrayWithObject:[NSNumber numberWithUnsignedInteger:[objectIDs count]]];

   NSMutableArray *objects=[NSMutableArray array];

   for(NSManagedObjectID *objectID in objectIDs)
    [objects addObject:[context objectWithID:objectID]];

   /* Only what SQL could not answer, over the rows it did. */
   if(residualPredicate!=nil)
    [objects filterUsingPredicate:residualPredicate];

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
     NSString     *deleteSQL=[NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = %lld",
                                                        quoted([join objectForKey:@"table"]),
                                                        quoted([join objectForKey:@"ownerColumn"]),
                                                        primaryKey];

     if(![self command:deleteSQL parameters:nil error:error])
      return NO;

     /* Both sides of a many-to-many rewrite the same join rows, so every
        insert carries BOTH order columns - otherwise whichever side saves
        last would wipe the other side's order. */
     NSRelationshipDescription *inverse=[relationship inverseRelationship];
     long long                  position=0;

     for(NSManagedObject *member in members){
      long long        memberKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:[member objectID]]);
      NSMutableString *columns=[NSMutableString stringWithFormat:@"%@, %@",
                                                                 quoted([join objectForKey:@"ownerColumn"]),
                                                                 quoted([join objectForKey:@"destinationColumn"])];
      NSMutableString *values=[NSMutableString stringWithFormat:@"%lld, %lld",primaryKey,memberKey];
      NSMutableArray  *updated=[NSMutableArray array];

      if([relationship isOrdered]){
       NSString *column=quoted(orderColumnForRelationship(relationship));

       [columns appendFormat:@", %@",column];
       [values appendFormat:@", %lld",position];
       [updated addObject:column];
      }

      if([inverse isOrdered]){
       NSString  *column=quoted(orderColumnForRelationship(inverse));
       id         memberSide=[member valueForKey:[inverse name]];
       NSUInteger inversePosition=(memberSide!=nil)?[memberSide indexOfObject:object]:NSNotFound;

       [columns appendFormat:@", %@",column];
       if(inversePosition!=NSNotFound)
        [values appendFormat:@", %llu",(unsigned long long)inversePosition];
       else
        [values appendString:@", NULL"];
       [updated addObject:column];
      }

      /* SQLite's INSERT OR REPLACE, as this database spells it. */
      NSString *insertSQL=[NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@)%@",
                                                     quoted([join objectForKey:@"table"]),columns,values,
                                                     [self upsertClauseForColumns:updated
                                                                       keyColumns:[NSArray arrayWithObjects:
                                                                                      quoted([join objectForKey:@"ownerColumn"]),
                                                                                      quoted([join objectForKey:@"destinationColumn"]),
                                                                                      nil]]];

      if(![self command:insertSQL parameters:nil error:error])
       return NO;
      position++;
     }
    }
    else {
     /* Foreign key on the destination table (the inverse is to-one). */
     NSRelationshipDescription *inverse=[relationship inverseRelationship];
     NSString                  *destinationTable=quoted(tableNameForEntity([relationship destinationEntity]));
     NSString                  *foreignKeyColumn=quoted(columnNameForProperty([inverse name]));
     NSString                  *clearSQL=[NSString stringWithFormat:@"UPDATE %@ SET %@ = NULL WHERE %@ = %lld",destinationTable,foreignKeyColumn,foreignKeyColumn,primaryKey];

     if(![self command:clearSQL parameters:nil error:error])
      return NO;

     long long position=0;

     for(NSManagedObject *member in members){
      long long memberKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:[member objectID]]);
      NSString *setSQL;

      if([relationship isOrdered])
       setSQL=[NSString stringWithFormat:@"UPDATE %@ SET %@ = %lld, %@ = %lld WHERE \"Z_PK\" = %lld",
                                         destinationTable,foreignKeyColumn,primaryKey,
                                         quoted(orderColumnForRelationship(relationship)),position,memberKey];
      else
       setSQL=[NSString stringWithFormat:@"UPDATE %@ SET %@ = %lld WHERE \"Z_PK\" = %lld",destinationTable,foreignKeyColumn,primaryKey,memberKey];

      if(![self command:setSQL parameters:nil error:error])
       return NO;
      position++;
     }
    }
   }

   return YES;
}

/* The row as it now stands in the database, for the persistedSnapshot of a
   merge conflict. */
-(NSDictionary *)_persistedSnapshotForObjectID:(NSManagedObjectID *)objectID {
   NSIncrementalStoreNode *node=[self _newNodeForObjectID:objectID error:NULL];

   if(node==nil)
    return nil;

   NSMutableDictionary *snapshot=[NSMutableDictionary dictionary];
   NSDictionary        *attributes=[[objectID entity] attributesByName];

   for(NSString *name in attributes){
    id value=[node valueForPropertyDescription:[attributes objectForKey:name]];

    if(value!=nil && value!=[NSNull null])
     [snapshot setObject:value forKey:name];
   }
   [node release];

   return snapshot;
}

/* Builds the conflict reported when an update found its row already
   changed.  cachedSnapshot is left nil: this store remembers the version of
   each row it has read but not the values, which the framework is holding
   anyway. */
-(NSMergeConflict *)_conflictForObject:(NSManagedObject *)object expectedVersion:(unsigned long long)expectedVersion {
   NSManagedObjectID *objectID=[object objectID];
   long long          primaryKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID]);
   NSString          *sql=[NSString stringWithFormat:@"SELECT \"Z_OPT\" FROM %@ WHERE \"Z_PK\" = %lld",quoted(tableNameForEntity([objectID entity])),primaryKey];
   id<CDSQLResult>    result=[self execute:sql parameters:nil error:NULL];
   unsigned long long currentVersion=0;

   if(result!=nil){
    if((int)[result rowCount]>0 && ![result isNullAtRow:0 column:0])
     currentVersion=(unsigned long long)[result longLongAtRow:0 column:0];
       }

   return [[[NSMergeConflict alloc] initWithSource:object
                                        newVersion:(NSUInteger)currentVersion
                                        oldVersion:(NSUInteger)expectedVersion
                                    cachedSnapshot:nil
                                 persistedSnapshot:(currentVersion!=0)?[self _persistedSnapshotForObjectID:objectID]:nil] autorelease];
}

-(BOOL)_writeRowForObject:(NSManagedObject *)object isInsert:(BOOL)isInsert conflict:(NSMergeConflict **)conflict error:(NSError **)error {
   NSEntityDescription *entity=[object entity];
   NSDictionary        *properties=propertiesForEntityChain(entity);
   long long            primaryKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:[object objectID]]);
   NSMutableArray      *names=[NSMutableArray array];
   NSMutableArray      *parameters=[NSMutableArray array];
   NSNumber            *expectedVersion=nil;

   for(NSString *name in [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)]){
    NSPropertyDescription *property=[properties objectForKey:name];
    id                     text=nil;

    if([property isKindOfClass:[NSAttributeDescription class]]){
     NSAttributeDescription *attribute=(NSAttributeDescription *)property;

     /* A generated column is computed by PostgreSQL and cannot be
        assigned. */
     if(generatedColumnSourceName(attribute,entity)!=nil)
      continue;

     text=textParameterForAttribute(attribute,[object valueForKey:name]);
    }
    else if([property isKindOfClass:[NSRelationshipDescription class]] && ![(NSRelationshipDescription *)property isToMany]){
     NSManagedObject *destination=[object valueForKey:name];

     if(destination!=nil)
      text=[NSString stringWithFormat:@"%lld",primaryKeyFromReferenceObject([self referenceObjectForObjectID:[destination objectID]])];
    }
    else
     continue;

    [names addObject:columnNameForProperty(name)];
    [parameters addObject:(text!=nil)?(id)text:(id)[NSNull null]];
   }

   NSString *sql;

   if(isInsert){
    NSMutableArray *columns=[NSMutableArray arrayWithObjects:@"\"Z_PK\"",@"\"Z_ENT\"",@"\"Z_OPT\"",nil];
    NSMutableArray *placeholders=[NSMutableArray array];
    NSUInteger      i,count=[names count];

    for(NSString *name in names)
     [columns addObject:quoted(name)];

    /* The three fixed columns are literals, so the placeholders line up
       with the parameter array built above. */
    [placeholders addObject:[NSString stringWithFormat:@"%lld",primaryKey]];
    [placeholders addObject:[NSString stringWithFormat:@"%lld",[self _entityIDForEntity:entity]]];
    [placeholders addObject:@"1"];

    for(i=0;i<count;i++)
     [placeholders addObject:[NSString stringWithFormat:@"$%lu",(unsigned long)(i+1)]];

    sql=[NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@)",quoted(tableNameForEntity(entity)),[columns componentsJoinedByString:@", "],[placeholders componentsJoinedByString:@", "]];
   }
   else {
    NSMutableArray *assignments=[NSMutableArray arrayWithObject:@"\"Z_OPT\" = \"Z_OPT\" + 1"];
    NSUInteger      i,count=[names count];

    for(i=0;i<count;i++)
     [assignments addObject:[NSString stringWithFormat:@"%@ = $%lu",quoted([names objectAtIndex:i]),(unsigned long)(i+1)]];

    /* Optimistic locking: when this store has read the row, the update is
       conditional on Z_OPT still being the version it read, so that a row
       changed by another client in the meantime is a reported conflict
       rather than a silent overwrite.  A row this store has never read
       carries no expectation and is written unconditionally. */
    expectedVersion=[_rowVersions objectForKey:[self _versionKeyForObjectID:[object objectID]]];

    if(expectedVersion!=nil)
     sql=[NSString stringWithFormat:@"UPDATE %@ SET %@ WHERE \"Z_PK\" = %lld AND \"Z_OPT\" = %llu",quoted(tableNameForEntity(entity)),[assignments componentsJoinedByString:@", "],primaryKey,[expectedVersion unsignedLongLongValue]];
    else
     sql=[NSString stringWithFormat:@"UPDATE %@ SET %@ WHERE \"Z_PK\" = %lld",quoted(tableNameForEntity(entity)),[assignments componentsJoinedByString:@", "],primaryKey];
   }

   long long affected=0;

   if(![self command:sql parameters:parameters affected:&affected error:error])
    return NO;

   if(!isInsert && expectedVersion!=nil && affected==0){
    if(conflict!=NULL)
     *conflict=[self _conflictForObject:object expectedVersion:[expectedVersion unsignedLongLongValue]];
    return NO;
   }

   /* The row now carries the next version. */
   if(isInsert)
    [_rowVersions setObject:[NSNumber numberWithUnsignedLongLong:1] forKey:[self _versionKeyForObjectID:[object objectID]]];
   else if(expectedVersion!=nil)
    [_rowVersions setObject:[NSNumber numberWithUnsignedLongLong:[expectedVersion unsignedLongLongValue]+1] forKey:[self _versionKeyForObjectID:[object objectID]]];

   /* To-many relationships are written by -_executeSaveRequest: after every
      row exists - an owner saved before its members would otherwise UPDATE
      rows that are not there yet. */
   return YES;
}

-(BOOL)_deleteRowForObject:(NSManagedObject *)object error:(NSError **)error {
   return [self _deleteRowWithEntity:[object entity]
                          primaryKey:primaryKeyFromReferenceObject([self referenceObjectForObjectID:[object objectID]])
                               error:error];
}

-(BOOL)_deleteRowWithEntity:(NSEntityDescription *)entity primaryKey:(long long)primaryKey error:(NSError **)error {
   NSDictionary *properties=propertiesForEntityChain(entity);

   /* Clean up join rows referencing the deleted row: those where it is the
      relationship's owner are found through its own relationships, those
      where it is the destination of another entity's inverse-less to-many
      must be swept from that relationship's side. */
   for(NSString *name in properties){
    NSPropertyDescription *property=[properties objectForKey:name];

    if(![property isKindOfClass:[NSRelationshipDescription class]])
     continue;

    if(relationshipUsesJoinTable((NSRelationshipDescription *)property)){
     NSDictionary *join=[self _joinSpecForRelationship:(NSRelationshipDescription *)property];
     NSString     *sql=[NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = %lld",quoted([join objectForKey:@"table"]),quoted([join objectForKey:@"ownerColumn"]),primaryKey];

     if(![self command:sql parameters:nil error:error])
      return NO;
    }
   }

   for(NSEntityDescription *check in [self _storeEntities]){
    for(NSRelationshipDescription *relationship in [[check relationshipsByName] allValues]){
     if(!relationshipUsesJoinTable(relationship) || [relationship inverseRelationship]!=nil)
      continue;
     if(!entityIsKindOfEntity(entity,[relationship destinationEntity]) && !entityIsKindOfEntity([relationship destinationEntity],entity))
      continue;

     NSDictionary *join=[self _joinSpecForRelationship:relationship];
     NSString     *sql=[NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = %lld",quoted([join objectForKey:@"table"]),quoted([join objectForKey:@"destinationColumn"]),primaryKey];

     if(![self command:sql parameters:nil error:error])
      return NO;
    }
   }

   NSString *sql=[NSString stringWithFormat:@"DELETE FROM %@ WHERE \"Z_PK\" = %lld",quoted(tableNameForEntity(entity)),primaryKey];

   [_rowVersions removeObjectForKey:[NSString stringWithFormat:@"%@/%lld",tableNameForEntity(entity),primaryKey]];

   return [self command:sql parameters:nil error:error];
}

-(id)_executeSaveRequest:(NSSaveChangesRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   if(![self command:@"BEGIN" parameters:nil error:error])
    return nil;

   for(NSManagedObject *object in [request insertedObjects]){
    if(![self _writeRowForObject:object isInsert:YES conflict:NULL error:error]){
     [self command:@"ROLLBACK" parameters:nil error:NULL];
     return nil;
    }
   }

   /* Every stale update is collected rather than the first one reported, so
      that the caller (or a merge policy) sees the whole picture. */
   NSMutableArray *conflicts=[NSMutableArray array];

   for(NSManagedObject *object in [request updatedObjects]){
    NSMergeConflict *conflict=nil;

    if(![self _writeRowForObject:object isInsert:NO conflict:&conflict error:error]){
     if(conflict==nil){
      [self command:@"ROLLBACK" parameters:nil error:NULL];
      return nil;
     }
     [conflicts addObject:conflict];
    }
   }

   if([conflicts count]>0){
    [self command:@"ROLLBACK" parameters:nil error:NULL];

    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain
                                code:NSPersistentStoreSaveConflictsError
                            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                         conflicts,NSPersistentStoreSaveConflictsErrorKey,
                                         @"The row was changed by another client since this store read it.",NSLocalizedDescriptionKey,
                                         nil]];
    return nil;
   }

   /* Every row exists now; write join rows and ordered positions. */
   for(NSManagedObject *object in [request insertedObjects]){
    if(![self _writeToManyRelationshipsForObject:object error:error]){
     [self command:@"ROLLBACK" parameters:nil error:NULL];
     return nil;
    }
   }

   for(NSManagedObject *object in [request updatedObjects]){
    if(![self _writeToManyRelationshipsForObject:object error:error]){
     [self command:@"ROLLBACK" parameters:nil error:NULL];
     return nil;
    }
   }

   /* Tombstones read the row's current values, so they are taken before
      the rows go. */
   NSMutableArray *deletedIDs=[NSMutableArray array];

   for(NSManagedObject *object in [request deletedObjects])
    [deletedIDs addObject:[object objectID]];

   NSDictionary *tombstones=[self _tombstonesForObjectIDs:deletedIDs];

   if(![self _recordHistoryForInserted:[request insertedObjects]
                               updated:[request updatedObjects]
                               deleted:[request deletedObjects]
                            tombstones:tombstones
                               context:context
                                 error:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    return nil;
   }

   for(NSManagedObject *object in [request deletedObjects]){
    if(![self _deleteRowForObject:object error:error]){
     [self command:@"ROLLBACK" parameters:nil error:NULL];
     return nil;
    }
   }

   if(![self _writeMetadata:[self metadata] error:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    return nil;
   }

   if(![self command:@"COMMIT" parameters:nil error:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    return nil;
   }

   if([[request insertedObjects] count]+[[request updatedObjects] count]+[[request deletedObjects] count]>0)
    [self _postRemoteChangeNotificationIfEnabled];

   return [NSArray array];
}

/* ------------------------------------------------------------------ */
#pragma mark - Batch requests
/* ------------------------------------------------------------------ */

/* Batch requests run straight against the database: no NSManagedObjects are
   materialized, no validation or delete rules run (beyond this store's own
   join-table cleanup), and loaded contexts are not notified. */

-(NSEntityDescription *)_batchEntityForName:(NSString *)name entity:(NSEntityDescription *)entity error:(NSError **)error {
   if(entity!=nil)
    return entity;

   NSEntityDescription *named=[[[[self persistentStoreCoordinator] managedObjectModel] entitiesByName] objectForKey:name];

   if(named==nil && error!=NULL)
    *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"batch request: no entity named '%@' in this model",name] forKey:NSLocalizedDescriptionKey]];

   return named;
}

/* The rows a batch update or delete applies to.  A predicate that does not
   translate to SQL is evaluated here instead, against each candidate row's
   stored values - the same fallback the fetch path uses, and the reason a
   batch request never silently applies to the wrong rows. */
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

   NSArray *objectIDs=[self _fetchObjectIDsForEntity:entity includesSubentities:includesSubentities whereSQL:whereSQL bindings:bindings orderBySQL:nil joins:nil fetchLimit:0 fetchOffset:0 error:error];

   if(objectIDs==nil || predicateInSQL)
    return objectIDs;

   NSMutableArray *result=[NSMutableArray array];

   for(NSManagedObjectID *objectID in objectIDs){
    NSIncrementalStoreNode *node=[self _newNodeForObjectID:objectID error:error];

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

    @try {
     matches=[predicate evaluateWithObject:row];
    } @catch(NSException *exception){
     matches=NO;
    }

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

     /* YES means "done"; that final dictionary is not inserted. */
     if(handler(row))
      break;

     [rows addObject:row];
    }
   }
   else if([request objectsToInsert]!=nil)
    [rows addObjectsFromArray:[request objectsToInsert]];

   NSDictionary *properties=propertiesForEntityChain(entity);

   if(![self command:@"BEGIN" parameters:nil error:error])
    return nil;

   NSMutableArray *insertedIDs=[NSMutableArray array];

   for(NSDictionary *row in rows){
    long long primaryKey=[self _nextPrimaryKeyForEntity:entity error:error];

    if(primaryKey==0){
     [self command:@"ROLLBACK" parameters:nil error:NULL];
     return nil;
    }

    NSMutableArray *columns=[NSMutableArray arrayWithObjects:@"\"Z_PK\"",@"\"Z_ENT\"",@"\"Z_OPT\"",nil];
    NSMutableArray *placeholders=[NSMutableArray arrayWithObjects:
                                     [NSString stringWithFormat:@"%lld",primaryKey],
                                     [NSString stringWithFormat:@"%lld",[self _entityIDForEntity:entity]],
                                     @"1",
                                     nil];
    NSMutableArray *parameters=[NSMutableArray array];

    for(NSString *name in [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)]){
     NSPropertyDescription *property=[properties objectForKey:name];

     if(![property isKindOfClass:[NSAttributeDescription class]])
      continue;   /* relationships cannot be batch inserted */

     NSAttributeDescription *attribute=(NSAttributeDescription *)property;

     if(generatedColumnSourceName(attribute,entity)!=nil)
      continue;   /* computed by PostgreSQL */

     id value=[row objectForKey:name];

     if(value==nil)
      value=[attribute defaultValue];
     if(value==nil)
      continue;

     id text=(value==[NSNull null])?nil:textParameterForAttribute(attribute,value);

     [columns addObject:quoted(columnNameForProperty(name))];
     [parameters addObject:(text!=nil)?(id)text:(id)[NSNull null]];
     [placeholders addObject:[NSString stringWithFormat:@"$%lu",(unsigned long)[parameters count]]];
    }

    NSString *sql=[NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@)",quoted(tableNameForEntity(entity)),[columns componentsJoinedByString:@", "],[placeholders componentsJoinedByString:@", "]];

    if(![self command:sql parameters:parameters error:error]){
     [self command:@"ROLLBACK" parameters:nil error:NULL];
     return nil;
    }

    [insertedIDs addObject:[[self newObjectIDForEntity:entity referenceObject:referenceObjectForPrimaryKey(primaryKey)] autorelease]];
   }

   if(![self _recordHistoryForObjectIDs:insertedIDs
                                   type:NSPersistentHistoryChangeTypeInsert
                             tombstones:nil
                                context:context
                                  error:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    return nil;
   }

   if(![self _writeMetadata:[self metadata] error:error] || ![self command:@"COMMIT" parameters:nil error:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    return nil;
   }

   if([insertedIDs count]>0)
    [self _postRemoteChangeNotificationIfEnabled];

   switch([request resultType]){
    case NSBatchInsertRequestResultTypeObjectIDs:
     return [[[CDBatchInsertResult alloc] initWithValue:insertedIDs type:NSBatchInsertRequestResultTypeObjectIDs] autorelease];
    case NSBatchInsertRequestResultTypeCount:
     return [[[CDBatchInsertResult alloc] initWithValue:[NSNumber numberWithUnsignedInteger:[insertedIDs count]] type:NSBatchInsertRequestResultTypeCount] autorelease];
    default:
     return [[[CDBatchInsertResult alloc] initWithValue:[NSNumber numberWithBool:YES] type:NSBatchInsertRequestResultTypeStatusOnly] autorelease];
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
   NSDictionary   *updates=[request propertiesToUpdate];
   NSMutableArray *assignments=[NSMutableArray arrayWithObject:@"\"Z_OPT\" = \"Z_OPT\" + 1"];
   NSMutableArray *parameters=[NSMutableArray array];

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

    id text=(value==nil || value==[NSNull null])?nil:textParameterForAttribute((NSAttributeDescription *)property,value);

    [parameters addObject:(text!=nil)?(id)text:(id)[NSNull null]];
    [assignments addObject:[NSString stringWithFormat:@"%@ = $%lu",quoted(columnNameForProperty(name)),(unsigned long)[parameters count]]];
   }

   if(![self command:@"BEGIN" parameters:nil error:error])
    return nil;

   /* The key list is chunked so that a batch over a very large table does
      not build one enormous statement. */
   NSUInteger chunkStart,total=[targetIDs count];

   for(chunkStart=0;chunkStart<total;chunkStart+=500){
    NSRange         range=NSMakeRange(chunkStart,MIN((NSUInteger)500,total-chunkStart));
    NSMutableArray *keys=[NSMutableArray array];

    for(NSManagedObjectID *objectID in [targetIDs subarrayWithRange:range])
     [keys addObject:[NSString stringWithFormat:@"%lld",primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID])]];

    NSString *sql=[NSString stringWithFormat:@"UPDATE %@ SET %@ WHERE \"Z_PK\" IN (%@)",quoted(tableNameForEntity(entity)),[assignments componentsJoinedByString:@", "],[keys componentsJoinedByString:@", "]];

    if(![self command:sql parameters:parameters error:error]){
     [self command:@"ROLLBACK" parameters:nil error:NULL];
     return nil;
    }
   }

   if(![self _recordHistoryForObjectIDs:targetIDs
                                   type:NSPersistentHistoryChangeTypeUpdate
                             tombstones:nil
                                context:context
                                  error:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    return nil;
   }

   if(![self _writeMetadata:[self metadata] error:error] || ![self command:@"COMMIT" parameters:nil error:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    return nil;
   }

   if(total>0)
    [self _postRemoteChangeNotificationIfEnabled];

   switch([request resultType]){
    case NSUpdatedObjectIDsResultType:
     return [[[CDBatchUpdateResult alloc] initWithValue:targetIDs type:NSUpdatedObjectIDsResultType] autorelease];
    case NSUpdatedObjectsCountResultType:
     return [[[CDBatchUpdateResult alloc] initWithValue:[NSNumber numberWithUnsignedInteger:total] type:NSUpdatedObjectsCountResultType] autorelease];
    default:
     return [[[CDBatchUpdateResult alloc] initWithValue:[NSNumber numberWithBool:YES] type:NSStatusOnlyResultType] autorelease];
   }
}

-(id)_executeBatchDeleteRequest:(NSBatchDeleteRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSFetchRequest      *fetch=[request fetchRequest];
   NSEntityDescription *entity=(fetch!=nil)?[self _entityForFetchRequest:fetch]:nil;

   if(entity==nil){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:@"batch delete: the fetch request has no entity" forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   /* An ID-based request (initWithObjectIDs:) arrives as a fetch request
      whose predicate is SELF IN <the ids>, which the translator turns into
      a primary key list. */
   NSArray *targetIDs=[self _batchTargetObjectIDsForEntity:entity predicate:[fetch predicate] includesSubentities:[fetch includesSubentities] error:error];

   if(targetIDs==nil)
    return nil;

   if(![self command:@"BEGIN" parameters:nil error:error])
    return nil;

   /* Read before the rows go, as in a save. */
   NSDictionary *tombstones=[self _tombstonesForObjectIDs:targetIDs];

   if(![self _recordHistoryForObjectIDs:targetIDs
                                   type:NSPersistentHistoryChangeTypeDelete
                             tombstones:tombstones
                                context:context
                                  error:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    return nil;
   }

   for(NSManagedObjectID *objectID in targetIDs){
    if(![self _deleteRowWithEntity:[objectID entity]
                        primaryKey:primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID])
                             error:error]){
     [self command:@"ROLLBACK" parameters:nil error:NULL];
     return nil;
    }
   }

   if(![self _writeMetadata:[self metadata] error:error] || ![self command:@"COMMIT" parameters:nil error:error]){
    [self command:@"ROLLBACK" parameters:nil error:NULL];
    return nil;
   }

   if([targetIDs count]>0)
    [self _postRemoteChangeNotificationIfEnabled];

   switch([request resultType]){
    case NSBatchDeleteResultTypeObjectIDs:
     return [[[CDBatchDeleteResult alloc] initWithValue:targetIDs type:NSBatchDeleteResultTypeObjectIDs] autorelease];
    case NSBatchDeleteResultTypeCount:
     return [[[CDBatchDeleteResult alloc] initWithValue:[NSNumber numberWithUnsignedInteger:[targetIDs count]] type:NSBatchDeleteResultTypeCount] autorelease];
    default:
     return [[[CDBatchDeleteResult alloc] initWithValue:[NSNumber numberWithBool:YES] type:NSBatchDeleteResultTypeStatusOnly] autorelease];
   }
}

-(id)executeRequest:(NSPersistentStoreRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   switch([request requestType]){

    case NSFetchRequestType:
     return [self _executeFetchRequest:(NSFetchRequest *)request withContext:context error:error];

    case NSSaveRequestType:
     return [self _executeSaveRequest:(NSSaveChangesRequest *)request withContext:context error:error];

    case NSBatchInsertRequestType:
     return [self _executeBatchInsertRequest:(NSBatchInsertRequest *)request withContext:context error:error];

    case NSBatchUpdateRequestType:
     return [self _executeBatchUpdateRequest:(NSBatchUpdateRequest *)request withContext:context error:error];

    case NSBatchDeleteRequestType:
     return [self _executeBatchDeleteRequest:(NSBatchDeleteRequest *)request withContext:context error:error];

    default:
     break;
   }

   /* Dispatched by class rather than by requestType: Apple does not publish
      an enum case for history at all (its requests answer 8, where this
      framework's answer 9), but the class is public on both. */
   if([request isKindOfClass:[NSPersistentHistoryChangeRequest class]])
    return [self _executeHistoryRequest:(NSPersistentHistoryChangeRequest *)request error:error];

   if(error!=NULL)
    *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@ does not support request type %lu",[self type],(unsigned long)[request requestType]] forKey:NSLocalizedDescriptionKey]];

   return nil;
}

/* ------------------------------------------------------------------ */
#pragma mark - Schema migration
/* ------------------------------------------------------------------ */

/* The framework's automatic migration copies a store through
   NSMigrationManager into a second store and then renames files over the
   first - which a database on the far end of a socket has none of.  So this
   store migrates itself, in place, by reconciling the tables it finds with
   the ones the model asks for.  See the README for the option an
   application passes to ask for it.
 
   What is reconciled: entities and properties added, removed or renamed
   (through renamingIdentifier), and attribute types that PostgreSQL can
   widen without losing anything.  Anything else - a changed inheritance
   chain, a type change that could lose data - is refused by name, and the
   answer for those is a mapping model and NSMigrationManager, which need
   nothing special from this store. */


/* The columns of a table as the database has them: name -> type, plus the
   names of the generated ones. */
-(NSDictionary *)_columnTypesForTable:(NSString *)table generated:(NSMutableSet *)generated {
   id<CDSQLResult> result=[self execute:[self columnsInTableSQL] parameters:[NSArray arrayWithObject:table] error:NULL];

   if(result==nil)
    return nil;

   NSMutableDictionary *columns=[NSMutableDictionary dictionary];
   int                  i,count=(int)[result rowCount];

   for(i=0;i<count;i++){
    NSString *name=[result stringAtRow:i column:0];

    [columns setObject:[result stringAtRow:i column:1] forKey:name];

    if(generated!=nil && [self introspectedColumnIsGenerated:[result stringAtRow:i column:2]])
     [generated addObject:name];
   }

   
   return columns;
}

-(NSArray *)_tableNamesInSchema {
   id<CDSQLResult> result=[self execute:[self tablesInSchemaSQL] parameters:nil error:NULL];

   if(result==nil)
    return [NSArray array];

   NSMutableArray *names=[NSMutableArray array];
   int             i,count=(int)[result rowCount];

   for(i=0;i<count;i++)
    [names addObject:[result stringAtRow:i column:0]];

   
   return names;
}

/* Whether the store was written by a model this one no longer matches.
   The question is asked of the framework, so that a store opened for one
   configuration is judged on that configuration's entities alone - which
   is what the coordinator would have done. */
-(BOOL)_needsMigrationForMetadata:(NSDictionary *)metadata {
   if([metadata objectForKey:NSStoreModelVersionHashesKey]==nil)
    return NO;   /* nothing to compare against */

   return ![[[self persistentStoreCoordinator] managedObjectModel]
               isConfiguration:[self configurationName] compatibleWithStoreMetadata:metadata];
}

-(BOOL)_failMigration:(NSError **)error reason:(NSString *)reason {
   if(error!=NULL)
    *error=[NSError errorWithDomain:NSCocoaErrorDomain
                               code:NSPersistentStoreIncompatibleSchemaError
                           userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@  Migrate with a mapping model and NSMigrationManager instead.",reason]
                                                                forKey:NSLocalizedDescriptionKey]];
   return NO;
}

/* Renames first: an entity or property that carries a renamingIdentifier
   naming something the store already has is the same thing under a new
   name, and its data is kept. */
-(BOOL)_applyEntityRenamesAmong:(NSArray *)entities error:(NSError **)error {
   for(NSEntityDescription *entity in entities){
    NSString *oldName=[entity renamingIdentifier];

    if(oldName==nil || [oldName isEqualToString:[entity name]])
     continue;
    if([_entityIDs objectForKey:[entity name]]!=nil)
     continue;   /* already renamed, or never had the old name */

    NSNumber *entityID=[_entityIDs objectForKey:oldName];

    if(entityID==nil)
     continue;   /* a new entity that happens to carry an identifier */

    if(![self _command:@"UPDATE \"Z_PRIMARYKEY\" SET \"Z_NAME\" = $1 WHERE \"Z_NAME\" = $2"
            parameters:[NSArray arrayWithObjects:[entity name],oldName,nil]
                 error:error])
     return NO;

    /* A root entity names its table, so that is renamed too. */
    if([entity superentity]==nil){
     NSString *oldTable=[@"Z" stringByAppendingString:[oldName uppercaseString]];

     if([self tableExists:oldTable] && ![self tableExists:tableNameForEntity(entity)] &&
        ![self _command:[NSString stringWithFormat:@"ALTER TABLE %@ RENAME TO %@",quoted(oldTable),quoted(tableNameForEntity(entity))] parameters:nil error:error])
      return NO;
    }

    [_entityIDs removeObjectForKey:oldName];
    [self _registerEntityID:[entityID longLongValue] forName:[entity name]];
   }

   return YES;
}

/* Reconciles one root entity's table with the columns the model asks for. */
-(BOOL)_migrateTableForRootEntity:(NSEntityDescription *)entity amongEntities:(NSArray *)entities error:(NSError **)error {
   NSString *table=tableNameForEntity(entity);
   NSArray  *specs=[self _columnSpecsForRootEntity:entity amongEntities:entities];

   if(![self tableExists:table]){
    NSMutableArray *columns=[NSMutableArray array];

    for(NSDictionary *spec in specs)
     [columns addObject:[self columnDefinitionFromSpec:spec]];

    return [self _command:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (%@)",quoted(table),[columns componentsJoinedByString:@", "]]
               parameters:nil
                    error:error];
   }

   NSMutableSet *generated=[NSMutableSet set];
   NSDictionary *actual=[self _columnTypesForTable:table generated:generated];
   NSMutableSet *expected=[NSMutableSet set];

   /* The old column name of a property that was renamed, so that its data
      can be carried across rather than dropped and re-added. */
   NSMutableDictionary *renamedFrom=[NSMutableDictionary dictionary];
   NSMutableDictionary *properties=[NSMutableDictionary dictionary];

   collectPropertiesOfEntitySubtree(entity,properties);

   for(NSString *name in properties){
    NSPropertyDescription *property=[properties objectForKey:name];
    NSString              *oldName=[property renamingIdentifier];

    if(oldName!=nil && ![oldName isEqualToString:name])
     [renamedFrom setObject:columnNameForProperty(oldName) forKey:columnNameForProperty(name)];
   }

   for(NSDictionary *spec in specs){
    NSString *name=[spec objectForKey:@"name"];
    NSString *type=[spec objectForKey:@"type"];
    NSString *generatedFrom=[spec objectForKey:@"generatedFrom"];
    NSString *existingType=[actual objectForKey:name];

    [expected addObject:name];

    if(existingType==nil){
     NSString *oldName=[renamedFrom objectForKey:name];

     if(oldName!=nil && [actual objectForKey:oldName]!=nil){
      if(![self command:[self renameColumnSQLForTable:table from:oldName definition:[self columnDefinitionFromSpec:spec]] parameters:nil error:error])
       return NO;

      /* The renamed column carries on through the checks below: a
         property can be renamed and retyped in the same version. */
      [expected addObject:oldName];   /* consumed by the rename */
      existingType=[actual objectForKey:oldName];
     }
     else {
      if(![self _command:[NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@",quoted(table),[self columnDefinitionFromSpec:spec]] parameters:nil error:error])
       return NO;
      continue;
     }
    }

    /* A column that became generated (or stopped being one) is rebuilt:
       its values are derived, so nothing is lost. */
    if((generatedFrom!=nil)!=[generated containsObject:name]){
     if(![self _command:[NSString stringWithFormat:@"ALTER TABLE %@ DROP COLUMN %@",quoted(table),quoted(name)] parameters:nil error:error] ||
        ![self _command:[NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@",quoted(table),[self columnDefinitionFromSpec:spec]] parameters:nil error:error])
      return NO;
     continue;
    }

    /* Both sides in the database's own spelling: the DDL type may carry a
       length or a collation that information_schema does not report. */
    if([existingType isEqualToString:[self introspectedTypeForColumnType:type]])
     continue;

    if(![self columnTypeChangeIsSafeFrom:existingType to:[self introspectedTypeForColumnType:type]])
     return [self _failMigration:error
                          reason:[NSString stringWithFormat:@"%@.%@ would change from %@ to %@, which could lose data.",[entity name],name,existingType,[self introspectedTypeForColumnType:type]]];

    if(![self command:[self changeColumnTypeSQLForTable:table column:name definition:[self columnDefinitionFromSpec:spec]] parameters:nil error:error])
     return NO;
   }

   /* Columns the model no longer has. */
   for(NSString *name in actual)
    if(![expected containsObject:name] &&
       ![self _command:[NSString stringWithFormat:@"ALTER TABLE %@ DROP COLUMN %@",quoted(table),quoted(name)] parameters:nil error:error])
     return NO;

   return YES;
}

-(BOOL)_migrateSchemaWithError:(NSError **)error {
   NSArray             *entities=[self _storeEntities];
   NSMutableDictionary *entitiesByName=[NSMutableDictionary dictionary];
   NSMutableArray      *sortedEntities=[NSMutableArray array];

   for(NSEntityDescription *entity in entities)
    [entitiesByName setObject:entity forKey:[entity name]];
   for(NSString *name in [[entitiesByName allKeys] sortedArrayUsingSelector:@selector(compare:)])
    [sortedEntities addObject:[entitiesByName objectForKey:name]];

   if(![self _applyEntityRenamesAmong:sortedEntities error:error])
    return NO;

   /* An entity the store has never seen gets the next free Z_ENT: the
      existing ones keep theirs, because every row records the one it was
      written with. */
   long long nextID=0;

   for(NSNumber *entityID in [_entityIDs allValues])
    nextID=MAX(nextID,[entityID longLongValue]);

   for(NSEntityDescription *entity in sortedEntities){
    if([_entityIDs objectForKey:[entity name]]!=nil)
     continue;

    NSEntityDescription *superentity=[entity superentity];
    long long            superID=(superentity!=nil)?[self _entityIDForEntity:superentity]:0;

    nextID++;

    if(![self _command:@"INSERT INTO \"Z_PRIMARYKEY\" (\"Z_ENT\", \"Z_NAME\", \"Z_SUPER\", \"Z_MAX\") VALUES ($1, $2, $3, 0)"
            parameters:[NSArray arrayWithObjects:
                           [NSString stringWithFormat:@"%lld",nextID],
                           [entity name],
                           [NSString stringWithFormat:@"%lld",superID],
                           nil]
                 error:error])
     return NO;

    [self _registerEntityID:nextID forName:[entity name]];
   }

   /* Entities that are gone from the MODEL - not merely from this store's
      configuration, whose tables belong to someone else and must be left
      alone.  Their bookkeeping row goes, and their table too when no
      entity is left using it. */
   NSDictionary *modelEntities=[[[self persistentStoreCoordinator] managedObjectModel] entitiesByName];
   NSMutableSet *liveTables=[NSMutableSet set];

   for(NSEntityDescription *entity in [modelEntities allValues])
    [liveTables addObject:tableNameForEntity(entity)];

   for(NSString *name in [[_entityIDs allKeys] copy]){
    if([modelEntities objectForKey:name]!=nil)
     continue;

    NSString *table=[@"Z" stringByAppendingString:[name uppercaseString]];

    if(![self _command:@"DELETE FROM \"Z_PRIMARYKEY\" WHERE \"Z_NAME\" = $1" parameters:[NSArray arrayWithObject:name] error:error])
     return NO;

    if(![liveTables containsObject:table] && [self tableExists:table] &&
       ![self _command:[self dropTableSQLForTable:table] parameters:nil error:error])
     return NO;

    [_entityNamesByID removeObjectForKey:[_entityIDs objectForKey:name]];
    [_entityIDs removeObjectForKey:name];
   }

   for(NSEntityDescription *entity in sortedEntities)
    if([entity superentity]==nil && ![self _migrateTableForRootEntity:entity amongEntities:sortedEntities error:error])
     return NO;

   /* Join tables: create the ones this configuration asks for, and keep
      every one the whole model still wants - a table belonging to another
      configuration is not ours to drop. */
   NSMutableSet *expectedJoins=[NSMutableSet set];

   for(NSEntityDescription *entity in [modelEntities allValues])
    for(NSRelationshipDescription *relationship in [[entity relationshipsByName] allValues])
     if(relationshipUsesJoinTable(relationship))
      [expectedJoins addObject:[[self _joinSpecForRelationship:relationship] objectForKey:@"table"]];

   for(NSEntityDescription *entity in sortedEntities)
    for(NSRelationshipDescription *relationship in [[entity relationshipsByName] allValues]){
     if(!relationshipUsesJoinTable(relationship))
      continue;

     NSDictionary *join=[self _joinSpecForRelationship:relationship];
     NSString     *table=[join objectForKey:@"table"];

     [expectedJoins addObject:table];

     if([self tableExists:table])
      continue;

     NSMutableString *columns=[NSMutableString stringWithFormat:@"%@ %@, %@ %@",
                                                                quoted([join objectForKey:@"ownerColumn"]),[self _bigIntegerType],
                                                                quoted([join objectForKey:@"destinationColumn"]),[self _bigIntegerType]];

     if([relationship isOrdered])
      [columns appendFormat:@", %@ %@",quoted(orderColumnForRelationship(relationship)),[self _bigIntegerType]];
     if([[relationship inverseRelationship] isOrdered])
      [columns appendFormat:@", %@ %@",quoted(orderColumnForRelationship([relationship inverseRelationship])),[self _bigIntegerType]];

     if(![self _command:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (%@, PRIMARY KEY (%@, %@))",
                                                   quoted(table),columns,
                                                   quoted([join objectForKey:@"ownerColumn"]),
                                                   quoted([join objectForKey:@"destinationColumn"])]
                parameters:nil error:error])
      return NO;
    }

   for(NSString *table in [self _tableNamesInSchema]){
    if(![table hasPrefix:@"Z_"] || [expectedJoins containsObject:table])
     continue;
    if([table isEqualToString:@"Z_METADATA"] || [table isEqualToString:@"Z_PRIMARYKEY"] ||
       [table isEqualToString:@"Z_ATRANSACTION"] || [table isEqualToString:@"Z_ACHANGE"])
     continue;

    if(![self _command:[self dropTableSQLForTable:table] parameters:nil error:error])
     return NO;
   }

   /* The store now matches the model, and says so. */
   NSManagedObjectModel *model=[[self persistentStoreCoordinator] managedObjectModel];
   NSMutableDictionary  *versionHashes=[NSMutableDictionary dictionary];
   NSMutableDictionary  *metadata=[NSMutableDictionary dictionaryWithDictionary:[self metadata]];

   for(NSEntityDescription *entity in entities)
    [versionHashes setObject:[entity versionHash] forKey:[entity name]];

   [metadata setObject:versionHashes forKey:NSStoreModelVersionHashesKey];
   [metadata setObject:[[model versionIdentifiers] allObjects] forKey:NSStoreModelVersionIdentifiersKey];
   [super setMetadata:metadata];

   return [self _writeMetadata:metadata error:error];
}

/* ------------------------------------------------------------------ */
#pragma mark - Persistent history
/* ------------------------------------------------------------------ */

/* The same two tables Apple's SQLite store keeps (and the one here does):
   one row per save, and one row per object changed by it. */
-(BOOL)_prepareHistoryTracking:(NSError **)error {
   if(!_historyTracking)
    return YES;

   if(![self tableExists:@"Z_ATRANSACTION"] &&
      ![self command:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS \"Z_ATRANSACTION\" (\"Z_PK\" %@ PRIMARY KEY, \"ZTIMESTAMP\" %@, \"ZAUTHOR\" %@, \"ZCONTEXTNAME\" %@, \"ZPROCESSID\" %@, \"ZBUNDLEID\" %@)",[self autoIncrementingPrimaryKeyType],[self _doubleType],[self _textType],[self _textType],[self _textType],[self _textType]] parameters:nil error:error])
    return NO;

   if(![self tableExists:@"Z_ACHANGE"] &&
      ![self command:[NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS \"Z_ACHANGE\" (\"Z_PK\" %@ PRIMARY KEY, \"ZTRANSACTIONID\" %@, \"ZCHANGETYPE\" %@, \"ZENTITY\" %@, \"ZENTITYPK\" %@, \"ZUPDATEDPROPERTIES\" %@, \"ZTOMBSTONE\" %@)",[self autoIncrementingPrimaryKeyType],[self _bigIntegerType],[self _integerType],[self _textType],[self _bigIntegerType],[self _textType],[self _blobType]] parameters:nil error:error])
    return NO;

   return YES;
}

/* The coordinator finds a store's history position through these two, by
   respondsToSelector:, which is how this addon joins in without the
   framework knowing anything about it. */
-(BOOL)_historyTrackingEnabled {
   return _historyTracking;
}

-(long long)_lastHistoryTransactionNumber {
   if(!_historyTracking || ![self tableExists:@"Z_ATRANSACTION"])
    return 0;

   id<CDSQLResult> result=[self execute:@"SELECT COALESCE(MAX(\"Z_PK\"), 0) FROM \"Z_ATRANSACTION\"" parameters:nil error:NULL];

   if(result==nil)
    return 0;

   long long number=((int)[result rowCount]>0 && ![result isNullAtRow:0 column:0])?[result longLongAtRow:0 column:0]:0;

   
   return number;
}

/* Opens a transaction row inside the caller's BEGIN/COMMIT and answers its
   number (0 on failure).  RETURNING gives the number back in the same
   statement. */
-(long long)_recordHistoryTransactionWithContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSString *author=[context transactionAuthor];
   NSString *contextName=[context name];
   NSString *processID=[NSString stringWithFormat:@"%d",(int)[[NSProcessInfo processInfo] processIdentifier]];
   NSString *bundleID=[[NSBundle mainBundle] bundleIdentifier];

   if(bundleID==nil)
    bundleID=[[NSProcessInfo processInfo] processName];

   NSArray *parameters=[NSArray arrayWithObjects:
                           [NSString stringWithFormat:@"%.17g",[[NSDate date] timeIntervalSinceReferenceDate]],
                           (author!=nil)?(id)author:(id)[NSNull null],
                           (contextName!=nil)?(id)contextName:(id)[NSNull null],
                           processID,
                           (bundleID!=nil)?(id)bundleID:(id)[NSNull null],
                           nil];

   return [self insertHistoryTransactionWithParameters:parameters error:error];
}

-(BOOL)_recordHistoryChangeInTransaction:(long long)transactionID
                                    type:(int)changeType
                                  entity:(NSEntityDescription *)entity
                              primaryKey:(long long)primaryKey
                       updatedProperties:(NSString *)updatedProperties
                               tombstone:(NSData *)tombstone
                                   error:(NSError **)error {
   NSArray *parameters=[NSArray arrayWithObjects:
                           [NSString stringWithFormat:@"%lld",transactionID],
                           [NSString stringWithFormat:@"%d",changeType],
                           [entity name],
                           [NSString stringWithFormat:@"%lld",primaryKey],
                           (updatedProperties!=nil)?(id)updatedProperties:(id)[NSNull null],
                           (tombstone!=nil)?parameterFromData(tombstone):(id)[NSNull null],
                           nil];

   return [self command:@"INSERT INTO \"Z_ACHANGE\" (\"ZTRANSACTIONID\", \"ZCHANGETYPE\", \"ZENTITY\", \"ZENTITYPK\", \"ZUPDATEDPROPERTIES\", \"ZTOMBSTONE\")"
       @" VALUES ($1, $2, $3, $4, $5, $6)" parameters:parameters error:error];
}

/* The tombstone for a deletion: the last values of the entity's attributes
   marked preservesValueInHistoryOnDeletion, as a binary property list keyed
   by attribute name; nil when the entity flags none. */
-(NSData *)_tombstoneForEntity:(NSEntityDescription *)entity values:(NSDictionary *)values {
   NSMutableDictionary *preserved=[NSMutableDictionary dictionary];

   for(NSAttributeDescription *attribute in [[entity attributesByName] allValues]){
    if(![attribute preservesValueInHistoryOnDeletion])
     continue;

    id value=[values objectForKey:[attribute name]];

    if(value!=nil && value!=[NSNull null])
     [preserved setObject:value forKey:[attribute name]];
   }

   if([preserved count]==0)
    return nil;

   return [NSPropertyListSerialization dataWithPropertyList:preserved format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}

-(void)_postRemoteChangeNotificationIfEnabled {
   if(!_postsRemoteChangeNotification)
    return;

   NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];

   if(_historyTracking && historySupportedByFramework()){
    NSDictionary *positions=[NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:[self _lastHistoryTransactionNumber]] forKey:[self identifier]];

    [userInfo setObject:[NSPersistentHistoryToken tokenWithTransactionNumbersByStoreIdentifier:positions] forKey:NSPersistentHistoryTokenKey];
   }
   if([self URL]!=nil)
    [userInfo setObject:[self URL] forKey:@"NSPersistentStoreURL"];

   [[NSNotificationCenter defaultCenter] postNotificationName:NSPersistentStoreRemoteChangeNotification object:[self persistentStoreCoordinator] userInfo:userInfo];
}

/* Records one transaction covering changes already written inside the
   caller's BEGIN/COMMIT.  Deletions hand in their tombstones, which have to
   be read before the rows go. */
-(BOOL)_recordHistoryForInserted:(id)inserted
                         updated:(id)updated
                         deleted:(id)deleted
                       tombstones:(NSDictionary *)tombstones
                         context:(NSManagedObjectContext *)context
                           error:(NSError **)error {
   if(!_historyTracking)
    return YES;

   NSUInteger changeCount=[inserted count]+[updated count]+[deleted count];

   if(changeCount==0)
    return YES;

   long long transactionID=[self _recordHistoryTransactionWithContext:context error:error];

   if(transactionID==0)
    return NO;

   for(NSManagedObject *object in inserted)
    if(![self _recordHistoryChangeInTransaction:transactionID
                                           type:NSPersistentHistoryChangeTypeInsert
                                         entity:[object entity]
                                     primaryKey:primaryKeyFromReferenceObject([self referenceObjectForObjectID:[object objectID]])
                              updatedProperties:nil
                                      tombstone:nil
                                          error:error])
     return NO;

   for(NSManagedObject *object in updated){
    NSArray  *changedKeys=[[[object changedValues] allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSString *updatedProperties=([changedKeys count]>0)?[changedKeys componentsJoinedByString:@","]:nil;

    if(![self _recordHistoryChangeInTransaction:transactionID
                                           type:NSPersistentHistoryChangeTypeUpdate
                                         entity:[object entity]
                                     primaryKey:primaryKeyFromReferenceObject([self referenceObjectForObjectID:[object objectID]])
                              updatedProperties:updatedProperties
                                      tombstone:nil
                                          error:error])
     return NO;
   }

   for(NSManagedObject *object in deleted)
    if(![self _recordHistoryChangeInTransaction:transactionID
                                           type:NSPersistentHistoryChangeTypeDelete
                                         entity:[object entity]
                                     primaryKey:primaryKeyFromReferenceObject([self referenceObjectForObjectID:[object objectID]])
                              updatedProperties:nil
                                      tombstone:[tombstones objectForKey:[object objectID]]
                                          error:error])
     return NO;

   return YES;
}

/* Records a transaction for a batch operation, which has object IDs rather
   than managed objects in hand. */
-(BOOL)_recordHistoryForObjectIDs:(NSArray *)objectIDs
                             type:(int)changeType
                       tombstones:(NSDictionary *)tombstones
                          context:(NSManagedObjectContext *)context
                            error:(NSError **)error {
   if(!_historyTracking || [objectIDs count]==0)
    return YES;

   long long transactionID=[self _recordHistoryTransactionWithContext:context error:error];

   if(transactionID==0)
    return NO;

   for(NSManagedObjectID *objectID in objectIDs)
    if(![self _recordHistoryChangeInTransaction:transactionID
                                           type:changeType
                                         entity:[objectID entity]
                                     primaryKey:primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID])
                              updatedProperties:nil
                                      tombstone:[tombstones objectForKey:objectID]
                                          error:error])
     return NO;

   return YES;
}

/* The tombstones for rows about to be deleted, keyed by object ID; empty
   when no entity involved preserves anything. */
-(NSDictionary *)_tombstonesForObjectIDs:(NSArray *)objectIDs {
   NSMutableDictionary *tombstones=[NSMutableDictionary dictionary];

   if(!_historyTracking)
    return tombstones;

   for(NSManagedObjectID *objectID in objectIDs){
    NSEntityDescription *entity=[objectID entity];
    BOOL                 wanted=NO;

    for(NSAttributeDescription *attribute in [[entity attributesByName] allValues])
     if([attribute preservesValueInHistoryOnDeletion]){
      wanted=YES;
      break;
     }

    if(!wanted)
     continue;

    NSIncrementalStoreNode *node=[self _newNodeForObjectID:objectID error:NULL];

    if(node==nil)
     continue;

    NSMutableDictionary *values=[NSMutableDictionary dictionary];
    NSDictionary        *attributes=[entity attributesByName];

    for(NSString *name in attributes){
     id value=[node valueForPropertyDescription:[attributes objectForKey:name]];

     if(value!=nil && value!=[NSNull null])
      [values setObject:value forKey:name];
    }
    [node release];

    NSData *tombstone=[self _tombstoneForEntity:entity values:values];

    if(tombstone!=nil)
     [tombstones setObject:tombstone forKey:objectID];
   }

   return tombstones;
}

-(NSPersistentHistoryTransaction *)_transactionFromRow:(NSDictionary *)row changes:(NSArray *)changes {
   return [NSPersistentHistoryTransaction transactionWithNumber:[[row objectForKey:@"number"] longLongValue]
                                                      timestamp:[row objectForKey:@"timestamp"]
                                                         author:[row objectForKey:@"author"]
                                                    contextName:[row objectForKey:@"contextName"]
                                                      processID:[row objectForKey:@"processID"]
                                                       bundleID:[row objectForKey:@"bundleID"]
                                                storeIdentifier:[self identifier]
                                                        changes:changes];
}

-(id)_executeHistoryRequest:(NSPersistentHistoryChangeRequest *)request error:(NSError **)error {
   if(!historySupportedByFramework()){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:@"Persistent history needs FreeCoreData: no public API says whether a history request is a fetch or a purge, nor what it is anchored to." forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   if(!_historyTracking){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:@"Persistent history tracking is not enabled on this store (NSPersistentHistoryTrackingKey)." forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   /* Resolve the anchor to either a transaction number or a timestamp. */
   long long anchorNumber=0;
   NSDate   *anchorDate=[request anchorDate];
   BOOL      byDate=(anchorDate!=nil);

   if(!byDate){
    if([request anchorTransactionNumber]>=0)
     anchorNumber=[request anchorTransactionNumber];
    else if([request token]!=nil)
     anchorNumber=[[request token] transactionNumberForStoreIdentifier:[self identifier]];
   }

   NSString *transactionCondition;

   if([request isPurgeRequest]){
    /* A purge removes strictly older transactions; the anchor's own
       transaction survives. */
    transactionCondition=byDate
        ?[NSString stringWithFormat:@"\"ZTIMESTAMP\" < %.17g",[anchorDate timeIntervalSinceReferenceDate]]
        :[NSString stringWithFormat:@"\"Z_PK\" < %lld",anchorNumber];

    if(![self command:[NSString stringWithFormat:@"DELETE FROM \"Z_ACHANGE\" WHERE \"ZTRANSACTIONID\" IN (SELECT \"Z_PK\" FROM \"Z_ATRANSACTION\" WHERE %@)",transactionCondition] parameters:nil error:error])
     return nil;
    if(![self command:[NSString stringWithFormat:@"DELETE FROM \"Z_ATRANSACTION\" WHERE %@",transactionCondition] parameters:nil error:error])
     return nil;

    return [[[CDPersistentHistoryResult alloc] initWithValue:[NSNumber numberWithBool:YES] type:NSPersistentHistoryResultTypeStatusOnly] autorelease];
   }

   /* The predicate-filtered flavor: the attached fetch request names one of
      the two synthetic history entities, and its predicate is evaluated
      against the materialized transaction/change objects, whose accessors
      are that entity's property names. */
   NSFetchRequest *filter=[request fetchRequest];
   BOOL            filtersTransactions=NO,filtersChanges=NO;

   if(filter!=nil){
    NSEntityDescription *filterEntity=[filter entity];

    if(filterEntity==[NSPersistentHistoryTransaction entityDescription])
     filtersTransactions=YES;
    else if(filterEntity==[NSPersistentHistoryChange entityDescription])
     filtersChanges=YES;
    else {
     if(error!=NULL)
      *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:@"fetchHistoryWithFetchRequest: requires a fetch request built on +[NSPersistentHistoryTransaction entityDescription] or +[NSPersistentHistoryChange entityDescription]." forKey:NSLocalizedDescriptionKey]];
     return nil;
    }

    /* Sort descriptors raise, as they do on Apple: results come back in
       transaction order. */
    if([[filter sortDescriptors] count]>0)
     [NSException raise:NSInvalidArgumentException
                 format:@"keypath %@ not found in entity TRANSACTION (history fetch requests do not support sort descriptors, matching Apple CoreData)",[[[filter sortDescriptors] objectAtIndex:0] key]];
   }

   NSPersistentHistoryResultType resultType=[request resultType];

   transactionCondition=byDate
       ?[NSString stringWithFormat:@"\"ZTIMESTAMP\" > %.17g",[anchorDate timeIntervalSinceReferenceDate]]
       :[NSString stringWithFormat:@"\"Z_PK\" > %lld",anchorNumber];

   id<CDSQLResult> result=[self execute:[NSString stringWithFormat:@"SELECT \"Z_PK\", \"ZTIMESTAMP\", \"ZAUTHOR\", \"ZCONTEXTNAME\", \"ZPROCESSID\", \"ZBUNDLEID\" FROM \"Z_ATRANSACTION\" WHERE %@ ORDER BY \"Z_PK\"",transactionCondition] parameters:nil error:error];

   if(result==nil)
    return nil;

   /* The rows are kept as they are read, and each transaction is built once
      its changes are in hand: a transaction adopts its changes when it is
      made, which is what wires up their -transaction back-pointers. */
   NSMutableArray *transactionRows=[NSMutableArray array];
   int             i,rowCount=(int)[result rowCount];

   for(i=0;i<rowCount;i++){
    NSString *(^text)(int)=^NSString *(int column){
      return [result isNullAtRow:i column:column]?nil:[result stringAtRow:i column:column];
     };
    NSMutableDictionary *row=[NSMutableDictionary dictionary];

    [row setObject:[NSNumber numberWithLongLong:[result longLongAtRow:i column:0]] forKey:@"number"];
    [row setObject:[NSDate dateWithTimeIntervalSinceReferenceDate:[result doubleAtRow:i column:1]] forKey:@"timestamp"];
    if(text(2)!=nil) [row setObject:text(2) forKey:@"author"];
    if(text(3)!=nil) [row setObject:text(3) forKey:@"contextName"];
    if(text(4)!=nil) [row setObject:text(4) forKey:@"processID"];
    if(text(5)!=nil) [row setObject:text(5) forKey:@"bundleID"];

    [transactionRows addObject:row];
   }

   
   /* A transaction-entity predicate is asked of a transaction, so those are
      built up front (without changes) to be filtered; the ones that survive
      are rebuilt below with whatever changes are wanted. */
   NSMutableArray *transactions=[NSMutableArray array];

   for(NSDictionary *row in transactionRows)
    [transactions addObject:[self _transactionFromRow:row changes:nil]];

   /* A transaction-entity predicate keeps whole transactions. */
   if(filtersTransactions && [filter predicate]!=nil){
    NSMutableArray *keptRows=[NSMutableArray array];
    NSUInteger      index=0;

    for(NSPersistentHistoryTransaction *transaction in transactions){
     if([[filter predicate] evaluateWithObject:transaction])
      [keptRows addObject:[transactionRows objectAtIndex:index]];
     index++;
    }

    transactionRows=keptRows;
    transactions=[NSMutableArray array];

    for(NSDictionary *row in transactionRows)
     [transactions addObject:[self _transactionFromRow:row changes:nil]];
   }

   BOOL wantsChanges=filtersChanges ||
       (resultType==NSPersistentHistoryResultTypeTransactionsAndChanges ||
        resultType==NSPersistentHistoryResultTypeChangesOnly ||
        resultType==NSPersistentHistoryResultTypeObjectIDs);

   NSDictionary   *entitiesByName=[[[self persistentStoreCoordinator] managedObjectModel] entitiesByName];
   NSMutableArray *keptTransactions=wantsChanges?[NSMutableArray array]:transactions;
   NSMutableArray *allChanges=[NSMutableArray array];
   NSMutableArray *allObjectIDs=[NSMutableArray array];

   if(wantsChanges)
   for(NSDictionary *row in transactionRows){
    id<CDSQLResult> changeResult=[self execute:@"SELECT \"Z_PK\", \"ZCHANGETYPE\", \"ZENTITY\", \"ZENTITYPK\", \"ZUPDATEDPROPERTIES\", \"ZTOMBSTONE\" FROM \"Z_ACHANGE\" WHERE \"ZTRANSACTIONID\" = $1 ORDER BY \"Z_PK\"" parameters:[NSArray arrayWithObject:[NSString stringWithFormat:@"%lld",[[row objectForKey:@"number"] longLongValue]]] error:error];

    if(changeResult==nil)
     return nil;

    NSMutableArray *changes=[NSMutableArray array];
    int             j,changeCount=(int)[changeResult rowCount];

    for(j=0;j<changeCount;j++){
     NSString            *entityName=[changeResult isNullAtRow:j column:2]?nil:[changeResult stringAtRow:j column:2];
     NSEntityDescription *entity=(entityName!=nil)?[entitiesByName objectForKey:entityName]:nil;

     if(entity==nil)
      continue;   /* recorded against an entity the current model lacks */

     NSManagedObjectID *objectID=[[self newObjectIDForEntity:entity referenceObject:referenceObjectForPrimaryKey([changeResult longLongAtRow:j column:3])] autorelease];
     NSMutableSet      *updatedProperties=nil;

     if(![changeResult isNullAtRow:j column:4]){
      NSDictionary *propertiesByName=[entity propertiesByName];

      updatedProperties=[NSMutableSet set];
      for(NSString *name in [[changeResult stringAtRow:j column:4] componentsSeparatedByString:@","]){
       NSPropertyDescription *property=[propertiesByName objectForKey:name];

       if(property!=nil)
        [updatedProperties addObject:property];
      }
     }

     NSDictionary *tombstone=nil;

     if(![changeResult isNullAtRow:j column:5]){
      NSData *data=[changeResult dataAtRow:j column:5];

      if([data length]>0)
       tombstone=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
     }

     NSPersistentHistoryChange *change=[NSPersistentHistoryChange
         changeWithID:[changeResult longLongAtRow:j column:0]
                 type:(NSPersistentHistoryChangeType)[changeResult longLongAtRow:j column:1]
             objectID:objectID
    updatedProperties:updatedProperties
            tombstone:tombstone];

     /* A change-entity predicate keeps individual changes. */
     if(filtersChanges && [filter predicate]!=nil && ![[filter predicate] evaluateWithObject:change])
      continue;

     [changes addObject:change];
     [allObjectIDs addObject:objectID];
    }

    
    /* A change-filtered transaction with nothing left is dropped. */
    if(filtersChanges && [changes count]==0)
     continue;

    /* Only a transactions-shaped result ties changes to their transaction:
       the back-pointer is unretained, so a flat changes result leaves it
       nil. */
    BOOL adopts=(resultType==NSPersistentHistoryResultTypeTransactionsAndChanges && !filtersChanges);

    [allChanges addObjectsFromArray:changes];
    [keptTransactions addObject:[self _transactionFromRow:row changes:adopts?changes:nil]];
   }

   /* A Change-entity fetch request answers the matching changes themselves,
      not transactions. */
   BOOL flatChanges=filtersChanges || (resultType==NSPersistentHistoryResultTypeChangesOnly);

   /* The fetch request's limit/offset apply to the result's top-level
      collection. */
   if(filter!=nil){
    NSMutableArray *topLevel=flatChanges?allChanges:keptTransactions;
    NSUInteger      offset=[filter fetchOffset];
    NSUInteger      limit=[filter fetchLimit];

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
     return [[[CDPersistentHistoryResult alloc] initWithValue:[NSNumber numberWithBool:YES] type:resultType] autorelease];
    case NSPersistentHistoryResultTypeCount:
     return [[[CDPersistentHistoryResult alloc] initWithValue:[NSNumber numberWithUnsignedInteger:flatChanges?[allChanges count]:[keptTransactions count]] type:resultType] autorelease];
    case NSPersistentHistoryResultTypeObjectIDs:
     return [[[CDPersistentHistoryResult alloc] initWithValue:allObjectIDs type:resultType] autorelease];
    case NSPersistentHistoryResultTypeChangesOnly:
     return [[[CDPersistentHistoryResult alloc] initWithValue:allChanges type:resultType] autorelease];
    case NSPersistentHistoryResultTypeTransactionsOnly:
     return [[[CDPersistentHistoryResult alloc] initWithValue:keptTransactions type:resultType] autorelease];
    default:
     return [[[CDPersistentHistoryResult alloc] initWithValue:flatChanges?allChanges:keptTransactions type:NSPersistentHistoryResultTypeTransactionsAndChanges] autorelease];
   }
}

/* ------------------------------------------------------------------ */
#pragma mark - Faulting
/* ------------------------------------------------------------------ */

-(long long)_entityIDOfRowWithPrimaryKey:(long long)primaryKey inTable:(NSString *)table {
   NSString *sql=[NSString stringWithFormat:@"SELECT \"Z_ENT\" FROM %@ WHERE \"Z_PK\" = %lld",quoted(table),primaryKey];
   id<CDSQLResult> result=[self execute:sql parameters:nil error:NULL];

   if(result==nil)
    return 0;

   long long entityID=((int)[result rowCount]>0 && ![result isNullAtRow:0 column:0])?[result longLongAtRow:0 column:0]:0;

   
   return entityID;
}

/* The key under which a row's version is remembered.  Object IDs cannot
   serve: a store hands out canonical instances, but an ID that reached the
   context from another coordinator is a different object with the same
   meaning, and identity would then miss.  The row's table and primary key
   identify it exactly. */
-(NSString *)_versionKeyForObjectID:(NSManagedObjectID *)objectID {
   return [NSString stringWithFormat:@"%@/%lld",
                                     tableNameForEntity([objectID entity]),
                                     primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID])];
}

/* The object ID for a row whose Z_ENT is already known, which is how the
   relationship queries below avoid a round trip per row. */
-(NSManagedObjectID *)_objectIDForPrimaryKey:(long long)primaryKey entityID:(long long)entityID declaredDestination:(NSEntityDescription *)declaredDestination {
   NSEntityDescription *entity=(entityID!=0)?[self _entityForEntityID:entityID]:nil;

   if(entity==nil)
    entity=declaredDestination;

   return [[self newObjectIDForEntity:entity referenceObject:referenceObjectForPrimaryKey(primaryKey)] autorelease];
}

-(NSManagedObjectID *)_objectIDForPrimaryKey:(long long)primaryKey declaredDestination:(NSEntityDescription *)declaredDestination {
   /* Only an entity that has subentities shares its table with rows of
      another concrete entity.  Without them the declared destination is
      already exact, and asking the database which entity a row belongs to
      would be a query per row for an answer that cannot vary. */
   if([[declaredDestination subentities] count]==0)
    return [[self newObjectIDForEntity:declaredDestination referenceObject:referenceObjectForPrimaryKey(primaryKey)] autorelease];

   return [self _objectIDForPrimaryKey:primaryKey
                              entityID:[self _entityIDOfRowWithPrimaryKey:primaryKey inTable:tableNameForEntity(declaredDestination)]
                   declaredDestination:declaredDestination];
}

-(NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   return [self _newNodeForObjectID:objectID error:error];
}

/* The body of -newValuesForObjectWithID:withContext:error:, reachable
   without a context: batch requests read stored rows with no context in
   hand, and that parameter is declared non-null. */
-(NSIncrementalStoreNode *)_newNodeForObjectID:(NSManagedObjectID *)objectID error:(NSError **)error {
   NSEntityDescription *entity=[objectID entity];
   NSDictionary        *properties=propertiesForEntityChain(entity);
   long long            primaryKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID]);
   NSMutableArray      *names=[NSMutableArray array];
   NSMutableArray      *selectColumns=[NSMutableArray arrayWithObject:@"\"Z_OPT\""];

   for(NSString *name in [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)]){
    NSPropertyDescription *property=[properties objectForKey:name];

    if([property isKindOfClass:[NSAttributeDescription class]] ||
       ([property isKindOfClass:[NSRelationshipDescription class]] && ![(NSRelationshipDescription *)property isToMany])){
     [names addObject:name];
     [selectColumns addObject:quoted(columnNameForProperty(name))];
    }
   }

   NSString *sql=[NSString stringWithFormat:@"SELECT %@ FROM %@ WHERE \"Z_PK\" = %lld",[selectColumns componentsJoinedByString:@", "],quoted(tableNameForEntity(entity)),primaryKey];
   id<CDSQLResult> result=[self execute:sql parameters:nil error:error];

   if(result==nil)
    return nil;

   if((int)[result rowCount]==0){
        if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSManagedObjectReferentialIntegrityError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"CoreData could not fulfill a fault for %@",objectID] forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   uint64_t             version=(uint64_t)[result longLongAtRow:0 column:0];
   NSMutableDictionary *values=[NSMutableDictionary dictionary];

   /* Remembered so that an update of this row can be made conditional on
      it still being the version this store handed out. */
   [_rowVersions setObject:[NSNumber numberWithUnsignedLongLong:version] forKey:[self _versionKeyForObjectID:objectID]];

   NSUInteger           i,count=[names count];

   for(i=0;i<count;i++){
    NSString              *name=[names objectAtIndex:i];
    NSPropertyDescription *property=[properties objectForKey:name];
    int                    column=(int)(i+1);

    if([property isKindOfClass:[NSAttributeDescription class]]){
     id value=attributeValueFromResult(result,0,column,(NSAttributeDescription *)property);

     if(value!=nil)
      [values setObject:value forKey:name];
    }
    else if(![result isNullAtRow:0 column:column])
     [values setObject:[self _objectIDForPrimaryKey:[result longLongAtRow:0 column:column] declaredDestination:[(NSRelationshipDescription *)property destinationEntity]] forKey:name];
   }

   
   return [[NSIncrementalStoreNode alloc] initWithObjectID:objectID withValues:values version:version];
}

-(id)newValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   long long            primaryKey=primaryKeyFromReferenceObject([self referenceObjectForObjectID:objectID]);
   NSEntityDescription *destination=[relationship destinationEntity];

   if(![relationship isToMany]){
    /* The destination row's Z_ENT comes back with the foreign key, so
       resolving a subentity costs no second round trip. */
    NSString *sql=[NSString stringWithFormat:@"SELECT t.%@, d.\"Z_ENT\" FROM %@ t LEFT JOIN %@ d ON d.\"Z_PK\" = t.%@ WHERE t.\"Z_PK\" = %lld",
                                             quoted(columnNameForProperty([relationship name])),
                                             quoted(tableNameForEntity([objectID entity])),
                                             quoted(tableNameForEntity(destination)),
                                             quoted(columnNameForProperty([relationship name])),
                                             primaryKey];
    id<CDSQLResult> result=[self execute:sql parameters:nil error:error];

    if(result==nil)
     return nil;

    id value=[NSNull null];

    if((int)[result rowCount]>0 && ![result isNullAtRow:0 column:0])
     value=[self _objectIDForPrimaryKey:[result longLongAtRow:0 column:0]
                               entityID:[result isNullAtRow:0 column:1]?0:[result longLongAtRow:0 column:1]
                    declaredDestination:destination];

    
    return [value retain];
   }

   NSString *sql;

   /* Both shapes select the destination's Z_ENT alongside its key: without
      it, resolving the concrete entity of an inherited destination would
      cost one query per element - the fault for a 500-element relationship
      would be 501 round trips. */
   if(relationshipUsesJoinTable(relationship)){
    NSDictionary *join=[self _joinSpecForRelationship:relationship];
    NSString     *orderBy=[relationship isOrdered]
        ?[NSString stringWithFormat:@" ORDER BY j.%@",quoted(orderColumnForRelationship(relationship))]
        :@"";

    sql=[NSString stringWithFormat:@"SELECT j.%@, d.\"Z_ENT\" FROM %@ j JOIN %@ d ON d.\"Z_PK\" = j.%@ WHERE j.%@ = %lld%@",
                                   quoted([join objectForKey:@"destinationColumn"]),
                                   quoted([join objectForKey:@"table"]),
                                   quoted(tableNameForEntity(destination)),
                                   quoted([join objectForKey:@"destinationColumn"]),
                                   quoted([join objectForKey:@"ownerColumn"]),
                                   primaryKey,orderBy];
   }
   else {
    NSRelationshipDescription *inverse=[relationship inverseRelationship];
    NSString                  *orderBy=[relationship isOrdered]
        ?quoted(orderColumnForRelationship(relationship))
        :@"\"Z_PK\"";

    sql=[NSString stringWithFormat:@"SELECT \"Z_PK\", \"Z_ENT\" FROM %@ WHERE %@ = %lld ORDER BY %@",
                                   quoted(tableNameForEntity(destination)),
                                   quoted(columnNameForProperty([inverse name])),
                                   primaryKey,orderBy];
   }

   id<CDSQLResult> result=[self execute:sql parameters:nil error:error];

   if(result==nil)
    return nil;

   NSMutableArray *objectIDs=[NSMutableArray array];
   int             i,count=(int)[result rowCount];

   for(i=0;i<count;i++)
    [objectIDs addObject:[self _objectIDForPrimaryKey:[result longLongAtRow:i column:0]
                                             entityID:[result isNullAtRow:i column:1]?0:[result longLongAtRow:i column:1]
                                  declaredDestination:destination]];

   
   return [[NSArray alloc] initWithArray:objectIDs];
}

/* ------------------------------------------------------------------ */
#pragma mark - Permanent IDs
/* ------------------------------------------------------------------ */

/* Reserves the next primary key by bumping Z_MAX on the root entity's
   Z_PRIMARYKEY row (subentities share the root's table and its key space).

   The SQLite store does this as an UPDATE followed by a SELECT, which is
   safe only because SQLite serializes writers.  RETURNING makes it one
   statement, so two connections cannot hand out the same key. */
-(long long)_nextPrimaryKeyForEntity:(NSEntityDescription *)entity error:(NSError **)error {
   long long primaryKey=[self allocatePrimaryKeyForRootEntityID:[self _entityIDForEntity:rootEntity(entity)] error:error];

   if(primaryKey==0 && error!=NULL && *error==nil)
    *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"No Z_PRIMARYKEY entry for entity %@",[entity name]] forKey:NSLocalizedDescriptionKey]];

   return primaryKey;
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
