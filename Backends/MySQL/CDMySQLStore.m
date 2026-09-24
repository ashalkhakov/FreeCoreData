/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

/* The MySQL half of a SQL store: the libmysqlclient driver, and the places
   where MySQL's SQL differs from PostgreSQL's.  Everything else is in
   CDSQLStore, which this subclasses.

   The client library is MariaDB Connector/C, which speaks to MySQL and
   MariaDB servers alike; libmysqlclient serves as well. */

#import "CDMySQLStore.h"

#import <mysql.h>
#import <errmsg.h>

NSString * const CDMySQLStoreType=@"CDMySQLStore";

/* Under this backend's own name, with the shared values. */
NSString * const CDMySQLSchemaNameOption=@"CDSQLStoreSchemaName";
NSString * const CDMySQLMigrateSchemaOption=@"CDSQLStoreMigrateSchema";

#define CONNECTION ((MYSQL *)_connection)

@interface CDMySQLStore (CDMySQLInternal)
-(long long)creationLockKeyForName:(NSString *)name;
@end

@interface CDMySQLResult : NSObject <CDSQLResult> {
   NSArray *_rows;   /* rows of NSData, or NSNull for a NULL column */
}
-(instancetype)initWithRows:(NSArray *)rows;
@end

@implementation CDMySQLResult

-(instancetype)initWithRows:(NSArray *)rows {
   if((self=[super init])==nil)
    return nil;
   _rows=[rows retain];
   return self;
}

-(void)dealloc {
   [_rows release];
   [super dealloc];
}

-(NSUInteger)rowCount {
   return [_rows count];
}

-(id)_valueAtRow:(NSUInteger)row column:(NSUInteger)column {
   if(row>=[_rows count])
    return [NSNull null];

   NSArray *values=[_rows objectAtIndex:row];

   return (column<[values count])?[values objectAtIndex:column]:[NSNull null];
}

-(BOOL)isNullAtRow:(NSUInteger)row column:(NSUInteger)column {
   return ([self _valueAtRow:row column:column]==[NSNull null]);
}

-(NSData *)dataAtRow:(NSUInteger)row column:(NSUInteger)column {
   id value=[self _valueAtRow:row column:column];

   return (value==[NSNull null])?nil:value;
}

-(NSString *)stringAtRow:(NSUInteger)row column:(NSUInteger)column {
   NSData *data=[self dataAtRow:row column:column];

   return (data!=nil)?[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]:nil;
}

-(long long)longLongAtRow:(NSUInteger)row column:(NSUInteger)column {
   return [[self stringAtRow:row column:column] longLongValue];
}

-(double)doubleAtRow:(NSUInteger)row column:(NSUInteger)column {
   return [[self stringAtRow:row column:column] doubleValue];
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - libmysqlclient helpers
/* ------------------------------------------------------------------ */


static NSError *mysqlError(MYSQL *connection,NSInteger code,NSString *message){
   const char *reason=(connection!=NULL)?mysql_error(connection):NULL;
   NSString   *detail=(reason!=NULL && *reason!='\0')?[NSString stringWithUTF8String:reason]:@"unknown MySQL error";

   return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@: %@",message,detail] forKey:NSLocalizedDescriptionKey]];
}

/* Whether a failed statement means the connection itself is gone, rather
   than the statement being wrong.  The error codes name the usual ways a
   server goes away, and the ping catches the rest - a TLS session that
   ended mid-read reports itself differently again. */
static BOOL mysqlConnectionIsLost(MYSQL *connection){
   if(connection==NULL)
    return YES;

   unsigned int code=mysql_errno(connection);

   if(code==CR_SERVER_GONE_ERROR || code==CR_SERVER_LOST || code==CR_CONN_HOST_ERROR)
    return YES;

   return (mysql_ping(connection)!=0);
}

/* One parameter as a SQL literal.  MySQL's text protocol has no numbered
   placeholders of its own, so the store's `$1`-style SQL is completed here,
   with every value escaped by the client library (a string) or written as a
   hex literal (binary).  Nothing else in this store ever emits a `$`. */
static NSString *mysqlLiteral(MYSQL *connection,id parameter){
   if(parameter==nil || parameter==[NSNull null])
    return @"NULL";

   if([parameter isKindOfClass:[NSData class]]){
    const unsigned char *bytes=[parameter bytes];
    NSUInteger           i,length=[parameter length];
    NSMutableString     *literal=[NSMutableString stringWithCapacity:length*2+3];

    [literal appendString:@"X'"];
    for(i=0;i<length;i++)
     [literal appendFormat:@"%02x",bytes[i]];
    [literal appendString:@"'"];

    return literal;
   }

   const char *utf8=[(NSString *)parameter UTF8String];
   unsigned long length=(unsigned long)strlen(utf8);
   char        *escaped=malloc(length*2+1);

   if(escaped==NULL)
    return @"NULL";

   unsigned long escapedLength=mysql_real_escape_string(connection,escaped,utf8,length);
   NSString     *literal=[NSString stringWithFormat:@"'%@'",[[[NSString alloc] initWithBytes:escaped length:escapedLength encoding:NSUTF8StringEncoding] autorelease]];

   free(escaped);

   return literal;
}

/* Replaces $1, $2 ... with the literals above. */
static NSString *mysqlCompleteSQL(MYSQL *connection,NSString *sql,NSArray *parameters){
   if([parameters count]==0)
    return sql;

   NSMutableString *result=[NSMutableString stringWithCapacity:[sql length]+32];
   NSUInteger       i,length=[sql length];

   for(i=0;i<length;i++){
    unichar character=[sql characterAtIndex:i];

    if(character!='$'){
     [result appendFormat:@"%C",character];
     continue;
    }

    NSUInteger index=0,digits=0;

    while(i+1<length){
     unichar digit=[sql characterAtIndex:i+1];

     if(digit<'0' || digit>'9')
      break;
     index=index*10+(digit-'0');
     digits++;
     i++;
    }

    if(digits==0 || index==0 || index>[parameters count]){
     [result appendString:@"$"];
     continue;
    }

    [result appendString:mysqlLiteral(connection,[parameters objectAtIndex:index-1])];
   }

   return result;
}


static BOOL myCommandOn(MYSQL *connection,NSString *sql,NSArray *parameters,NSError **error);

static CDMySQLResult *myRunSQL(MYSQL *connection,NSString *sql,NSArray *parameters,NSError **error){
   NSString   *completed=mysqlCompleteSQL(connection,sql,parameters);
   const char *utf8=[completed UTF8String];

   if(mysql_real_query(connection,utf8,(unsigned long)strlen(utf8))!=0){
    if(error!=NULL)
     *error=mysqlError(connection,NSPersistentStoreOperationError,[NSString stringWithFormat:@"'%@' failed",sql]);
    return nil;
   }

   MYSQL_RES *raw=mysql_store_result(connection);

   if(raw==NULL){
    /* A statement with no result set: an error only when one was meant. */
    if(mysql_field_count(connection)!=0){
     if(error!=NULL)
      *error=mysqlError(connection,NSPersistentStoreOperationError,[NSString stringWithFormat:@"'%@' returned no result",sql]);
     return nil;
    }

    return [[[CDMySQLResult alloc] initWithRows:[NSArray array]] autorelease];
   }

   NSMutableArray *rows=[NSMutableArray array];
   unsigned int    columns=mysql_num_fields(raw);
   MYSQL_ROW       row;

   while((row=mysql_fetch_row(raw))!=NULL){
    unsigned long  *lengths=mysql_fetch_lengths(raw);
    NSMutableArray *values=[NSMutableArray arrayWithCapacity:columns];
    unsigned int    column;

    for(column=0;column<columns;column++){
     if(row[column]==NULL)
      [values addObject:[NSNull null]];
     else
      [values addObject:[NSData dataWithBytes:row[column] length:lengths[column]]];
    }

    [rows addObject:values];
   }

   mysql_free_result(raw);

   return [[[CDMySQLResult alloc] initWithRows:rows] autorelease];
}


/* One query parameter of the store URL, or nil. */
static NSString *queryItemFromURL(NSURL *url,NSString *name){
   for(NSString *pair in [[url query] componentsSeparatedByString:@"&"]){
    NSRange separator=[pair rangeOfString:@"="];

    if(separator.location==NSNotFound)
     continue;
    if([[pair substringToIndex:separator.location] isEqualToString:name])
     return [[pair substringFromIndex:NSMaxRange(separator)] stringByRemovingPercentEncoding];
   }

   return nil;
}

static NSString *databaseNameFromURL(NSURL *url,NSDictionary *options){
   NSString *schema=[options objectForKey:CDSQLStoreSchemaNameOption];

   if(schema!=nil)
    return schema;

   NSString *path=[url path];

   return ([path length]>1)?[path substringFromIndex:1]:nil;
}

/* The name of the lock that serializes creating a database or a store's
   tables.  MySQL's GET_LOCK takes a string rather than a number, and its
   locks are held by the session until released - there is no
   transaction-scoped form as in PostgreSQL, which is why every path below
   that takes one also gives it back. */
static NSString *creationLockName(CDMySQLStore *store,NSString *database){
   return [NSString stringWithFormat:@"'coredata_%lld'",[store creationLockKeyForName:database]];
}

static BOOL myCommandOn(MYSQL *connection,NSString *sql,NSArray *parameters,NSError **error){
   return (myRunSQL(connection,sql,parameters,error)!=nil);
}

static MYSQL *myConnect(CDMySQLStore *store,NSURL *url,NSDictionary *options,NSError **error){
   if(url==nil || [url host]==nil){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreInvalidTypeError userInfo:[NSDictionary dictionaryWithObject:@"CDMySQLStoreType requires a mysql://user:password@host/database URL" forKey:NSLocalizedDescriptionKey]];
    return NULL;
   }

   NSString *database=databaseNameFromURL(url,options);

   /* MySQL truncates an identifier past 64 characters rather than refusing
      it, so two long names agreeing on their first 64 would quietly become
      one database. */
   if([database lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>64){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreInvalidTypeError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The database name '%@' is longer than MySQL's 64-character limit for identifiers, and would be truncated.",database] forKey:NSLocalizedDescriptionKey]];
    return NULL;
   }

   MYSQL *connection=mysql_init(NULL);

   if(connection==NULL){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOpenError userInfo:[NSDictionary dictionaryWithObject:@"out of memory opening a MySQL connection" forKey:NSLocalizedDescriptionKey]];
    return NULL;
   }

   /* A MySQL client treats the host name "localhost" as an instruction to
      use a local socket, whatever port was asked for.  A store URL names a
      server to reach over the network, so say so. */
   unsigned int protocol=MYSQL_PROTOCOL_TCP;

   mysql_options(connection,MYSQL_OPT_PROTOCOL,&protocol);

   /* TLS, as sslmode in the URL asks for it:
 
        disable      no TLS at all
        require      TLS, without checking who is on the other end (the
                     default, and what a server's own self-signed
                     certificate supports)
        verify-ca    TLS, and the certificate must be signed by sslrootcert
        verify-full  the same, and the host name must match
 
      The default is deliberately not verify-ca: a server that has never
      been given a certificate answers with a self-signed one, and refusing
      to talk to it at all would make the common case unusable.  A
      deployment that cares says so in the URL. */
   NSString *sslMode=queryItemFromURL(url,@"sslmode");
   NSString *sslRootCertificate=queryItemFromURL(url,@"sslrootcert");

   if(sslMode==nil)
    sslMode=@"require";

   if(![sslMode isEqualToString:@"disable"]){
    my_bool enforce=1;

    mysql_options(connection,MYSQL_OPT_SSL_ENFORCE,&enforce);

    my_bool verify=([sslMode isEqualToString:@"verify-ca"] || [sslMode isEqualToString:@"verify-full"])?1:0;

    mysql_options(connection,MYSQL_OPT_SSL_VERIFY_SERVER_CERT,&verify);

    if(sslRootCertificate!=nil)
     mysql_options(connection,MYSQL_OPT_SSL_CA,[sslRootCertificate UTF8String]);
   }

   /* Connect without naming a database: the one wanted may still have to be
      created below. */
   if(mysql_real_connect(connection,
                         [[url host] UTF8String],
                         ([[url user] length]>0)?[[url user] UTF8String]:NULL,
                         ([[url password] length]>0)?[[url password] UTF8String]:NULL,
                         NULL,
                         ([url port]!=nil)?[[url port] unsignedIntValue]:3306,
                         NULL,
                         0)==NULL){
    if(error!=NULL)
     *error=mysqlError(connection,NSPersistentStoreOpenError,[NSString stringWithFormat:@"unable to connect to %@",[url host]]);
    mysql_close(connection);
    return NULL;
   }

   mysql_set_character_set(connection,"utf8mb4");

   /* Identifiers are quoted the way the shared core writes them - "like
      this" - which MySQL reads as a string unless it is asked for
      ANSI_QUOTES.  Appending keeps whatever else the server was set to,
      strict mode included. */
   if(!myCommandOn(connection,@"SET sql_mode=CONCAT(@@sql_mode,',ANSI_QUOTES')",nil,error)){
    mysql_close(connection);
    return NULL;
   }

   if(database==nil){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreInvalidTypeError userInfo:[NSDictionary dictionaryWithObject:@"the store URL names no database" forKey:NSLocalizedDescriptionKey]];
    mysql_close(connection);
    return NULL;
   }

   /* CREATE DATABASE IF NOT EXISTS is not atomic against another connection
      running it at the same moment, so it is serialized the same way table
      creation is. */
   NSString *lock=creationLockName(store,database);

   if(!myCommandOn(connection,[NSString stringWithFormat:@"SELECT GET_LOCK(%@, 30)",lock],nil,error)){
    mysql_close(connection);
    return NULL;
   }

   BOOL created=myCommandOn(connection,[NSString stringWithFormat:@"CREATE DATABASE IF NOT EXISTS %@ CHARACTER SET utf8mb4",[store quoted:database]],nil,error);

   myCommandOn(connection,[NSString stringWithFormat:@"SELECT RELEASE_LOCK(%@)",lock],nil,NULL);

   if(!created){
    mysql_close(connection);
    return NULL;
   }

   if(mysql_select_db(connection,[database UTF8String])!=0){
    if(error!=NULL)
     *error=mysqlError(connection,NSPersistentStoreOpenError,[NSString stringWithFormat:@"unable to use the database %@",database]);
    mysql_close(connection);
    return NULL;
   }

   return connection;
}


@implementation CDMySQLStore

/* Linking the library is enough to make the store type available. */
+(void)load {
   [NSPersistentStoreCoordinator registerStoreClass:self forStoreType:CDMySQLStoreType];
}

+(NSString *)type {
   return CDMySQLStoreType;
}

-(NSString *)type {
   return CDMySQLStoreType;
}

/* ------------------------------------------------------------------ */
#pragma mark - Driver
/* ------------------------------------------------------------------ */

-(long long)creationLockKeyForName:(NSString *)name {
   return [self lockKeyForName:name];
}

/* The database this store lives in, which is what MySQL calls a schema. */
-(NSString *)_databaseName {
   return databaseNameFromURL([self URL],[self options]);
}

-(BOOL)openConnectionWithURL:(NSURL *)url options:(NSDictionary *)options error:(NSError **)error {
   MYSQL *connection=myConnect(self,url,options,error);

   if(connection==NULL)
    return NO;

   if(_connection!=NULL)
    mysql_close(CONNECTION);
   _connection=connection;

   return YES;
}

-(void)closeConnection {
   if(_connection!=NULL){
    mysql_close(CONNECTION);
    _connection=NULL;
   }
}

-(id<CDSQLResult>)runSQL:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
   return myRunSQL(CONNECTION,sql,parameters,error);
}

-(long long)rowsAffected {
   return (long long)mysql_affected_rows(CONNECTION);
}

-(BOOL)connectionIsLost {
   return mysqlConnectionIsLost(CONNECTION);
}

/* libmysqlclient has no PQreset: a new handle is made and swapped in, which
   is why nothing in the store holds on to one across statements.
   Reopening goes through the same code as opening, so the database is
   selected and the session set up again. */
-(BOOL)reopenConnectionWithError:(NSError **)error {
   return [self openConnectionWithURL:[self URL] options:[self options] error:error];
}

/* ------------------------------------------------------------------ */
#pragma mark - Dialect
/* ------------------------------------------------------------------ */

-(NSUInteger)maximumIdentifierLength {
   return 64;
}

-(NSString *)schemaConceptName {
   return @"database";
}

-(NSString *)columnTypeForAttributeType:(NSUInteger)attributeType {
   switch(attributeType){
    case NSInteger16AttributeType:      return @"smallint";
    case NSInteger32AttributeType:      return @"int";
    case NSInteger64AttributeType:      return @"bigint";
    case NSBooleanAttributeType:        return @"tinyint(1)";
    case NSDoubleAttributeType:         return @"double";
    case NSFloatAttributeType:          return @"float";
    /* MySQL needs a precision where PostgreSQL's numeric takes none; 65
       digits is its maximum, 20 of them after the point. */
    case NSDecimalAttributeType:        return @"decimal(65,20)";
    /* A binary collation, so that =, LIKE and ORDER BY compare by code
       point as NSString does.  MySQL's default collations are
       case-insensitive, which would quietly change what a fetch returns. */
    case NSStringAttributeType:
    case NSURIAttributeType:            return @"text collate utf8mb4_bin";
    case NSUUIDAttributeType:           return @"char(36)";
    case NSDateAttributeType:           return @"double";
    case NSBinaryDataAttributeType:
    case NSTransformableAttributeType:
    default:                            return @"longblob";
   }
}

/* information_schema reports the bare type, without the length or the
   collation a column definition may carry. */
-(NSString *)introspectedTypeForColumnType:(NSString *)columnType {
   NSRange    parenthesis=[columnType rangeOfString:@"("];
   NSRange    collate=[columnType rangeOfString:@" collate " options:NSCaseInsensitiveSearch];
   NSUInteger end=[columnType length];

   if(parenthesis.location!=NSNotFound)
    end=MIN(end,parenthesis.location);
   if(collate.location!=NSNotFound)
    end=MIN(end,collate.location);

   return [[columnType substringToIndex:end] lowercaseString];
}

-(NSString *)autoIncrementingPrimaryKeyType {
   return @"bigint AUTO_INCREMENT";
}

-(BOOL)columnTypeChangeIsSafeFrom:(NSString *)from to:(NSString *)to {
   NSDictionary *widenings=[NSDictionary dictionaryWithObjectsAndKeys:
       [NSArray arrayWithObjects:@"smallint",@"int",@"bigint",@"float",@"double",@"decimal",@"text",nil],@"tinyint",
       [NSArray arrayWithObjects:@"int",@"bigint",@"float",@"double",@"decimal",@"text",nil],@"smallint",
       [NSArray arrayWithObjects:@"bigint",@"double",@"decimal",@"text",nil],@"int",
       [NSArray arrayWithObjects:@"decimal",@"text",nil],@"bigint",
       [NSArray arrayWithObjects:@"double",@"decimal",@"text",nil],@"float",
       [NSArray arrayWithObjects:@"decimal",@"text",nil],@"double",
       [NSArray arrayWithObjects:@"text",nil],@"decimal",
       [NSArray arrayWithObjects:@"text",nil],@"char",
       nil];

   return [[widenings objectForKey:from] containsObject:to];
}

/* A backslash escapes inside a MySQL string literal, so the escape
   character reaches the server doubled. */
-(NSString *)likeEscapeClause {
   return @" ESCAPE '\\\\'";
}

/* Text columns carry a binary collation, so LIKE is case-sensitive as
   NSString is; the case-insensitive half folds both sides instead, which no
   collation can then undo. */
-(NSString *)caseInsensitiveLikeClauseForColumn:(NSString *)column placeholder:(NSString *)placeholder {
   return [NSString stringWithFormat:@"LOWER(%@) LIKE LOWER(%@)%@",column,placeholder,[self likeEscapeClause]];
}

-(NSString *)caseSensitiveLikeClauseForColumn:(NSString *)column placeholder:(NSString *)placeholder {
   return [NSString stringWithFormat:@"%@ LIKE %@%@",column,placeholder,[self likeEscapeClause]];
}

/* Nothing to add: the column's own collation is already binary, so an
   ordered comparison follows code points.  Where the PostgreSQL store asks
   for the C collation at each site, this one asks once, in the schema. */
-(NSString *)codePointOrderedColumn:(NSString *)column isText:(BOOL)isText {
   return column;
}

/* No conflict target: the primary key is the one that can clash. */
-(NSString *)upsertClauseForColumns:(NSArray *)columns keyColumns:(NSArray *)keyColumns {
   NSMutableArray *assignments=[NSMutableArray array];

   for(NSString *column in columns)
    [assignments addObject:[NSString stringWithFormat:@"%@ = VALUES(%@)",column,column]];

   if([assignments count]==0){
    NSString *key=[keyColumns objectAtIndex:0];

    /* MySQL has no DO NOTHING; assigning a key column to itself is the
       usual way to say it. */
    [assignments addObject:[NSString stringWithFormat:@"%@ = %@",key,key]];
   }

   return [NSString stringWithFormat:@" ON DUPLICATE KEY UPDATE %@",[assignments componentsJoinedByString:@", "]];
}

/* MySQL has no RETURNING (MariaDB does, but not MySQL), so the increment
   happens inside LAST_INSERT_ID(), which makes the new value readable from
   the same connection - and, like RETURNING, without a window in which
   another connection could hand out the same key. */
-(long long)allocatePrimaryKeyForRootEntityID:(long long)entityID error:(NSError **)error {
   NSString *sql=[NSString stringWithFormat:@"UPDATE \"Z_PRIMARYKEY\" SET \"Z_MAX\" = LAST_INSERT_ID(\"Z_MAX\" + 1) WHERE \"Z_ENT\" = %lld",entityID];

   if(![self command:sql parameters:nil error:error])
    return 0;

   return (long long)mysql_insert_id(CONNECTION);
}

-(long long)insertHistoryTransactionWithParameters:(NSArray *)parameters error:(NSError **)error {
   if(![self command:@"INSERT INTO \"Z_ATRANSACTION\" (\"ZTIMESTAMP\", \"ZAUTHOR\", \"ZCONTEXTNAME\", \"ZPROCESSID\", \"ZBUNDLEID\")"
              @" VALUES ($1, $2, $3, $4, $5)" parameters:parameters error:error])
    return 0;

   return (long long)mysql_insert_id(CONNECTION);
}

-(NSString *)tableExistsSQL {
   return @"SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = $1";
}

-(NSString *)columnsInTableSQL {
   return @"SELECT column_name, data_type, extra FROM information_schema.columns"
          @" WHERE table_schema = DATABASE() AND table_name = $1";
}

-(NSString *)tablesInSchemaSQL {
   return @"SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE()";
}

/* MySQL says so in EXTRA ("STORED GENERATED"), where PostgreSQL has a
   column of its own. */
-(BOOL)introspectedColumnIsGenerated:(NSString *)flag {
   return ([flag rangeOfString:@"GENERATED"].location!=NSNotFound);
}

/* CHANGE rather than RENAME COLUMN, which older MySQL and MariaDB do not
   have; it restates the column, which is what the definition holds. */
-(NSString *)renameColumnSQLForTable:(NSString *)table from:(NSString *)oldName definition:(NSString *)definition {
   return [NSString stringWithFormat:@"ALTER TABLE %@ CHANGE %@ %@",[self quoted:table],[self quoted:oldName],definition];
}

-(NSString *)changeColumnTypeSQLForTable:(NSString *)table column:(NSString *)column definition:(NSString *)definition {
   return [NSString stringWithFormat:@"ALTER TABLE %@ MODIFY COLUMN %@",[self quoted:table],definition];
}

-(NSString *)dropTableSQLForTable:(NSString *)table {
   return [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@",[self quoted:table]];
}

-(BOOL)dropSchemaWithError:(NSError **)error {
   return [self command:[NSString stringWithFormat:@"DROP DATABASE IF EXISTS %@",[self quoted:[self schemaName]]] parameters:nil error:error];
}

/* MySQL's locks are held by the session rather than by the transaction, so
   this one is given back by hand - and, because MySQL commits DDL as it
   goes, the lock rather than the transaction is what makes creating a store
   safe against another client doing it at the same moment. */
-(BOOL)takeCreationLockWithError:(NSError **)error {
   return [self command:[NSString stringWithFormat:@"SELECT GET_LOCK('coredata_%lld', 30)",[self creationLockKeyForName:[self _databaseName]]] parameters:nil error:error];
}

-(void)releaseCreationLock {
   [self command:[NSString stringWithFormat:@"SELECT RELEASE_LOCK('coredata_%lld')",[self creationLockKeyForName:[self _databaseName]]] parameters:nil error:NULL];
}

/* Values are escaped into the statement text rather than bound, so there
   is no parameter count to run out of - only max_allowed_packet, which is
   megabytes.  The number is a sanity bound, not a protocol limit. */
-(NSUInteger)maximumBoundParameters {
   return 200000;
}

-(BOOL)runsDDLInTransactions {
   return NO;
}

@end
