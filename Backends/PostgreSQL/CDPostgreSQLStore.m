/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

/* The PostgreSQL half of a SQL store: the libpq driver, and the places
   where PostgreSQL's SQL differs from the next database's.  Everything
   else - the schema, faulting, predicates, saving, batch requests,
   locking, history, migration - is in CDSQLStore, which this subclasses. */

#import "CDPostgreSQLStore.h"

#import <libpq-fe.h>

NSString * const CDPostgreSQLStoreType=@"CDPostgreSQLStore";

/* The option keys under this backend's own name; the values are the shared
   ones, so a store reads them whichever spelling an application uses. */
NSString * const CDPostgreSQLSchemaNameOption=@"CDSQLStoreSchemaName";
NSString * const CDPostgreSQLMigrateSchemaOption=@"CDSQLStoreMigrateSchema";

#define CONNECTION ((PGconn *)_connection)

/* ------------------------------------------------------------------ */
#pragma mark - Results
/* ------------------------------------------------------------------ */

@interface CDPostgreSQLResult : NSObject <CDSQLResult> {
   PGresult *_result;
}
-(instancetype)initWithResult:(PGresult *)result;
@end

@implementation CDPostgreSQLResult

-(instancetype)initWithResult:(PGresult *)result {
   if((self=[super init])==nil)
    return nil;
   _result=result;
   return self;
}

-(void)dealloc {
   if(_result!=NULL)
    PQclear(_result);
   [super dealloc];
}

-(NSUInteger)rowCount {
   return (NSUInteger)PQntuples(_result);
}

-(BOOL)isNullAtRow:(NSUInteger)row column:(NSUInteger)column {
   return PQgetisnull(_result,(int)row,(int)column)?YES:NO;
}

-(NSString *)stringAtRow:(NSUInteger)row column:(NSUInteger)column {
   if([self isNullAtRow:row column:column])
    return nil;

   return [NSString stringWithUTF8String:PQgetvalue(_result,(int)row,(int)column)];
}

-(long long)longLongAtRow:(NSUInteger)row column:(NSUInteger)column {
   return atoll(PQgetvalue(_result,(int)row,(int)column));
}

-(double)doubleAtRow:(NSUInteger)row column:(NSUInteger)column {
   return atof(PQgetvalue(_result,(int)row,(int)column));
}

/* bytea comes back in its text form, which libpq turns back into bytes. */
-(NSData *)dataAtRow:(NSUInteger)row column:(NSUInteger)column {
   if([self isNullAtRow:row column:column])
    return nil;

   size_t         length=0;
   unsigned char *bytes=PQunescapeBytea((const unsigned char *)PQgetvalue(_result,(int)row,(int)column),&length);

   if(bytes==NULL)
    return nil;

   NSData *data=[NSData dataWithBytes:bytes length:length];

   PQfreemem(bytes);

   return data;
}

@end

@implementation CDPostgreSQLStore

/* Linking the library is enough to make the store type available. */
+(void)load {
   [NSPersistentStoreCoordinator registerStoreClass:self forStoreType:CDPostgreSQLStoreType];
}

+(NSString *)type {
   return CDPostgreSQLStoreType;
}

-(NSString *)type {
   return CDPostgreSQLStoreType;
}

/* ------------------------------------------------------------------ */
#pragma mark - Driver
/* ------------------------------------------------------------------ */

static NSError *postgresError(PGconn *connection,NSInteger code,NSString *message){
   const char *reason=(connection!=NULL)?PQerrorMessage(connection):NULL;
   NSString   *detail=(reason!=NULL && *reason!='\0')?[NSString stringWithUTF8String:reason]:@"unknown PostgreSQL error";

   return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@: %@",message,detail] forKey:NSLocalizedDescriptionKey]];
}

/* A parameter in the text form libpq sends: binary values as the "\x..."
   literal PostgreSQL reads back as bytea. */
static NSString *postgresParameterText(id parameter){
   if(![parameter isKindOfClass:[NSData class]])
    return parameter;

   const unsigned char *bytes=[parameter bytes];
   NSUInteger           i,length=[parameter length];
   NSMutableString     *text=[NSMutableString stringWithCapacity:length*2+2];

   [text appendString:@"\\x"];
   for(i=0;i<length;i++)
    [text appendFormat:@"%02x",bytes[i]];

   return text;
}

-(BOOL)openConnectionWithURL:(NSURL *)url options:(NSDictionary *)options error:(NSError **)error {
   if(url==nil){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreInvalidTypeError userInfo:[NSDictionary dictionaryWithObject:@"CDPostgreSQLStoreType requires a postgresql:// URL" forKey:NSLocalizedDescriptionKey]];
    return NO;
   }

   NSString *schema=[options objectForKey:CDSQLStoreSchemaNameOption];

   /* PostgreSQL truncates an identifier longer than NAMEDATALEN-1 rather
      than refusing it, so two long schema names agreeing on their first 63
      bytes would quietly become one schema. */
   if([schema lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>[self maximumIdentifierLength]){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreInvalidTypeError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The %@ name '%@' is longer than PostgreSQL's %lu-byte limit for identifiers, and would be truncated.",[self schemaConceptName],schema,(unsigned long)[self maximumIdentifierLength]] forKey:NSLocalizedDescriptionKey]];
    return NO;
   }

   /* libpq parses the URI itself, so the store URL goes as written. */
   PGconn *connection=PQconnectdb([[url absoluteString] UTF8String]);

   if(connection==NULL || PQstatus(connection)!=CONNECTION_OK){
    if(error!=NULL)
     *error=postgresError(connection,NSPersistentStoreOpenError,[NSString stringWithFormat:@"unable to connect to %@",url]);
    if(connection!=NULL)
     PQfinish(connection);
    return NO;
   }

   if(_connection!=NULL)
    PQfinish(CONNECTION);
   _connection=connection;

   if(schema!=nil && ![self _createAndSelectSchema:schema error:error]){
    PQfinish(CONNECTION);
    _connection=NULL;
    return NO;
   }

   return YES;
}

/* CREATE SCHEMA IF NOT EXISTS is no more atomic than CREATE TABLE IF NOT
   EXISTS: two connections running it together fail with a duplicate key on
   pg_namespace, so it is serialized by a lock of the same kind. */
-(BOOL)_createAndSelectSchema:(NSString *)schema error:(NSError **)error {
   NSString *key=[NSString stringWithFormat:@"%lld",[self creationLockKey]];

   if(![self command:[NSString stringWithFormat:@"SELECT pg_advisory_lock(%@)",key] parameters:nil error:error])
    return NO;

   BOOL created=[self command:[NSString stringWithFormat:@"CREATE SCHEMA IF NOT EXISTS %@",[self quoted:schema]] parameters:nil error:error];

   [self command:[NSString stringWithFormat:@"SELECT pg_advisory_unlock(%@)",key] parameters:nil error:NULL];

   if(!created)
    return NO;

   return [self command:[NSString stringWithFormat:@"SET search_path TO %@",[self quoted:schema]] parameters:nil error:error];
}

-(void)closeConnection {
   if(_connection!=NULL){
    PQfinish(CONNECTION);
    _connection=NULL;
   }
}

-(id<CDSQLResult>)runSQL:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
   int          count=(int)[parameters count];
   const char **values=(count>0)?calloc((size_t)count,sizeof(char *)):NULL;
   int          i;

   for(i=0;i<count;i++){
    id parameter=[parameters objectAtIndex:(NSUInteger)i];

    values[i]=(parameter==[NSNull null])?NULL:[postgresParameterText(parameter) UTF8String];
   }

   PGresult *result=PQexecParams(CONNECTION,[sql UTF8String],count,NULL,values,NULL,NULL,0);

   if(values!=NULL)
    free(values);

   ExecStatusType status=(result!=NULL)?PQresultStatus(result):PGRES_FATAL_ERROR;

   if(status!=PGRES_COMMAND_OK && status!=PGRES_TUPLES_OK){
    if(error!=NULL)
     *error=postgresError(CONNECTION,NSPersistentStoreOperationError,[NSString stringWithFormat:@"'%@' failed",sql]);
    if(result!=NULL)
     PQclear(result);
    return nil;
   }

   /* PQcmdTuples belongs to the result, which the caller may let go before
      asking how many rows changed, so the count is kept here. */
   const char *tuples=PQcmdTuples(result);

   _rowsAffected=(tuples!=NULL && tuples[0]!='\0')?atoll(tuples):0;

   return [[[CDPostgreSQLResult alloc] initWithResult:result] autorelease];
}

-(long long)rowsAffected {
   return _rowsAffected;
}

-(BOOL)connectionIsLost {
   return (_connection==NULL || PQstatus(CONNECTION)!=CONNECTION_OK);
}

/* PQreset reuses the connection object with the parameters it was made
   with, so every PGconn * this store holds stays valid; the session state
   it does not carry over is put back. */
-(BOOL)reopenConnectionWithError:(NSError **)error {
   if(_connection==NULL)
    return NO;

   PQreset(CONNECTION);

   if(PQstatus(CONNECTION)!=CONNECTION_OK)
    return NO;

   if([self schemaName]!=nil)
    return [self command:[NSString stringWithFormat:@"SET search_path TO %@",[self quoted:[self schemaName]]] parameters:nil error:error];

   return YES;
}

/* ------------------------------------------------------------------ */
#pragma mark - Dialect
/* ------------------------------------------------------------------ */

-(NSUInteger)maximumIdentifierLength {
   return 63;
}

-(NSString *)schemaConceptName {
   return @"schema";
}

-(NSString *)columnTypeForAttributeType:(NSUInteger)attributeType {
   switch(attributeType){
    case NSInteger16AttributeType:      return @"smallint";
    case NSInteger32AttributeType:      return @"integer";
    case NSInteger64AttributeType:      return @"bigint";
    case NSBooleanAttributeType:        return @"boolean";
    case NSDoubleAttributeType:         return @"double precision";
    case NSFloatAttributeType:          return @"real";
    case NSDecimalAttributeType:        return @"numeric";
    case NSStringAttributeType:
    case NSURIAttributeType:            return @"text";
    case NSUUIDAttributeType:           return @"uuid";
    case NSDateAttributeType:           return @"double precision";
    case NSBinaryDataAttributeType:
    case NSTransformableAttributeType:
    default:                            return @"bytea";
   }
}

-(NSString *)introspectedTypeForColumnType:(NSString *)columnType {
   return columnType;   /* information_schema uses the same names */
}

-(NSString *)autoIncrementingPrimaryKeyType {
   return @"bigserial";
}

/* Widening only: every conversion here keeps the value it started with. */
-(BOOL)columnTypeChangeIsSafeFrom:(NSString *)from to:(NSString *)to {
   NSDictionary *widenings=[NSDictionary dictionaryWithObjectsAndKeys:
       [NSArray arrayWithObjects:@"integer",@"bigint",@"real",@"double precision",@"numeric",@"text",nil],@"smallint",
       [NSArray arrayWithObjects:@"bigint",@"double precision",@"numeric",@"text",nil],@"integer",
       [NSArray arrayWithObjects:@"numeric",@"text",nil],@"bigint",
       [NSArray arrayWithObjects:@"double precision",@"numeric",@"text",nil],@"real",
       [NSArray arrayWithObjects:@"numeric",@"text",nil],@"double precision",
       [NSArray arrayWithObjects:@"text",nil],@"numeric",
       [NSArray arrayWithObjects:@"text",nil],@"boolean",
       [NSArray arrayWithObjects:@"text",nil],@"uuid",
       nil];

   return [[widenings objectForKey:from] containsObject:to];
}

-(NSString *)likeEscapeClause {
   return @" ESCAPE '\\'";
}

/* PostgreSQL's LIKE is case-sensitive and ILIKE is its case-insensitive
   twin, so both halves of a wildcard match are one operator. */
-(NSString *)caseInsensitiveLikeClauseForColumn:(NSString *)column placeholder:(NSString *)placeholder {
   return [NSString stringWithFormat:@"%@ ILIKE %@%@",column,placeholder,[self likeEscapeClause]];
}

-(NSString *)caseSensitiveLikeClauseForColumn:(NSString *)column placeholder:(NSString *)placeholder {
   return [NSString stringWithFormat:@"%@ LIKE %@%@",column,placeholder,[self likeEscapeClause]];
}

/* NSString's -compare: orders by code point.  A database created with a
   language collation (en_US.utf8, say) orders "alan" before "Grace"
   instead, so an ordered comparison on text asks for the C collation. */
-(NSString *)codePointOrderedColumn:(NSString *)column isText:(BOOL)isText {
   if(!isText)
    return column;

   return [NSString stringWithFormat:@"%@ COLLATE \"C\"",column];
}

-(NSString *)upsertClauseForColumns:(NSArray *)columns keyColumns:(NSArray *)keyColumns {
   if([columns count]==0)
    return [NSString stringWithFormat:@" ON CONFLICT (%@) DO NOTHING",[keyColumns componentsJoinedByString:@", "]];

   NSMutableArray *assignments=[NSMutableArray array];

   for(NSString *column in columns)
    [assignments addObject:[NSString stringWithFormat:@"%@ = EXCLUDED.%@",column,column]];

   return [NSString stringWithFormat:@" ON CONFLICT (%@) DO UPDATE SET %@",
                                     [keyColumns componentsJoinedByString:@", "],
                                     [assignments componentsJoinedByString:@", "]];
}

/* RETURNING makes this one statement, so two connections cannot hand out
   the same key. */
-(long long)allocatePrimaryKeyForRootEntityID:(long long)entityID error:(NSError **)error {
   NSString        *sql=[NSString stringWithFormat:@"UPDATE \"Z_PRIMARYKEY\" SET \"Z_MAX\" = \"Z_MAX\" + 1 WHERE \"Z_ENT\" = %lld RETURNING \"Z_MAX\"",entityID];
   id<CDSQLResult>  result=[self execute:sql parameters:nil error:error];

   if(result==nil || [result rowCount]==0)
    return 0;

   return [result longLongAtRow:0 column:0];
}

-(long long)insertHistoryTransactionWithParameters:(NSArray *)parameters error:(NSError **)error {
   id<CDSQLResult> result=[self execute:@"INSERT INTO \"Z_ATRANSACTION\" (\"ZTIMESTAMP\", \"ZAUTHOR\", \"ZCONTEXTNAME\", \"ZPROCESSID\", \"ZBUNDLEID\")"
       @" VALUES ($1, $2, $3, $4, $5) RETURNING \"Z_PK\"" parameters:parameters error:error];

   if(result==nil || [result rowCount]==0)
    return 0;

   return [result longLongAtRow:0 column:0];
}

-(NSString *)tableExistsSQL {
   return @"SELECT 1 FROM information_schema.tables WHERE table_schema = ANY (current_schemas(false)) AND table_name = $1";
}

-(NSString *)columnsInTableSQL {
   return @"SELECT column_name, data_type, is_generated FROM information_schema.columns"
          @" WHERE table_schema = ANY (current_schemas(false)) AND table_name = $1";
}

-(NSString *)tablesInSchemaSQL {
   return @"SELECT table_name FROM information_schema.tables WHERE table_schema = ANY (current_schemas(false))";
}

-(BOOL)introspectedColumnIsGenerated:(NSString *)flag {
   return [flag isEqualToString:@"ALWAYS"];
}

-(NSString *)renameColumnSQLForTable:(NSString *)table from:(NSString *)oldName definition:(NSString *)definition {
   NSString *newName=[[definition componentsSeparatedByString:@" "] objectAtIndex:0];

   return [NSString stringWithFormat:@"ALTER TABLE %@ RENAME COLUMN %@ TO %@",[self quoted:table],[self quoted:oldName],newName];
}

-(NSString *)changeColumnTypeSQLForTable:(NSString *)table column:(NSString *)column definition:(NSString *)definition {
   NSArray  *words=[definition componentsSeparatedByString:@" "];
   NSString *type=[[words subarrayWithRange:NSMakeRange(1,[words count]-1)] componentsJoinedByString:@" "];

   return [NSString stringWithFormat:@"ALTER TABLE %@ ALTER COLUMN %@ TYPE %@ USING %@::%@",
                                     [self quoted:table],[self quoted:column],type,[self quoted:column],type];
}

-(NSString *)dropTableSQLForTable:(NSString *)table {
   return [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@ CASCADE",[self quoted:table]];
}

-(BOOL)dropSchemaWithError:(NSError **)error {
   return [self command:[NSString stringWithFormat:@"DROP SCHEMA IF EXISTS %@ CASCADE",[self quoted:[self schemaName]]] parameters:nil error:error];
}

/* The lock is taken for the transaction, so the COMMIT (or a rollback, or
   the connection dying) gives it back without any unlock of ours. */
-(BOOL)takeCreationLockWithError:(NSError **)error {
   return [self command:[NSString stringWithFormat:@"SELECT pg_advisory_xact_lock(%lld)",[self creationLockKey]] parameters:nil error:error];
}

-(void)releaseCreationLock {
}

-(BOOL)runsDDLInTransactions {
   return YES;
}

@end
