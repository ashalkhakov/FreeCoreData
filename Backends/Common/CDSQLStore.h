/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreData/CoreData.h>

/* The SQL half of a persistent store, shared by the backends that speak to
   a SQL database over a network.

   Everything that does not depend on which database is at the other end
   lives here: the schema (the same one the in-tree SQLite store keeps),
   object IDs, faulting, predicate and sort translation, saving,
   relationship writing, batch requests, optimistic locking, persistent
   history and in-place migration.  That is the great majority of a
   backend.

   A backend subclasses CDSQLStore and supplies two things: a driver (open a
   connection, run a statement, read a result, reopen after a drop) and a
   dialect (how this database spells the handful of things SQL databases
   disagree about).  Both are the methods below marked "subclasses".

   The division is not a guess: it is what was left over after the
   PostgreSQL and MySQL backends were written independently and compared.

   This is public-API-only code - it builds against Apple's CoreData as
   well as this framework - with one exception, persistent history, which
   needs API that only FreeCoreData publishes and is switched off when it is
   not there. */

@protocol CDSQLResult;

/* The option keys a backend publishes under its own name; the values are
   shared, so a store reads them with either spelling. */
extern NSString * const CDSQLStoreSchemaNameOption;
extern NSString * const CDSQLStoreMigrateSchemaOption;

@interface CDSQLStore : NSIncrementalStore {
    NSString *_schemaName;                  /* the schema, or database, if any */
    NSMutableDictionary *_entityIDs;        /* entity name -> NSNumber (Z_ENT) */
    NSMutableDictionary *_entityNamesByID;  /* NSNumber (Z_ENT) -> entity name */
    NSMutableDictionary *_rowVersions;      /* "table/pk" -> NSNumber (Z_OPT) */
    BOOL _historyTracking;
    BOOL _postsRemoteChangeNotification;
    BOOL _inTransaction;
}

/* Drops everything this store owns at `url`: the whole schema when the
   options name one, otherwise the store's own Z_ tables.  For tests and for
   tools that need to start from a clean database; there is no Core Data API
   for destroying a store. */
+ (BOOL)destroyStoreAtURL:(NSURL *)url options:(NSDictionary *)options error:(NSError **)error;

@end

/* ------------------------------------------------------------------ */
/* Running statements: what a backend's dialect and driver call back    */
/* into.                                                               */
/* ------------------------------------------------------------------ */

@interface CDSQLStore (CDSQLStatements)

/* Run a statement, with `$1`-style placeholders filled from `parameters`
   (NSString, NSData or NSNull).  Reconnects and tries again when the
   connection was lost and no transaction of ours was open. */
- (id<CDSQLResult>)execute:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error;
- (BOOL)command:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error;
- (BOOL)command:(NSString *)sql parameters:(NSArray *)parameters affected:(long long *)affected error:(NSError **)error;
- (BOOL)tableExists:(NSString *)name;

/* An identifier, quoted the way both dialects accept (MySQL is asked for
   ANSI_QUOTES when it connects). */
- (NSString *)quoted:(NSString *)identifier;

/* The schema (in MySQL, the database) this store was confined to, or nil. */
- (NSString *)schemaName;

/* A stable key derived from the schema name, for whatever kind of lock the
   dialect uses to serialize creating a store. */
- (long long)creationLockKey;
- (long long)lockKeyForName:(NSString *)name;

@end

/* ------------------------------------------------------------------ */
/* What a backend supplies: the driver.                               */
/* ------------------------------------------------------------------ */

@interface CDSQLStore (CDSQLDriver)

/* Open a connection for this store's URL and options, or answer NO.  A
   subclass also creates and selects the schema or database here, and sets
   up whatever session state it needs. */
- (BOOL)openConnectionWithURL:(NSURL *)url options:(NSDictionary *)options error:(NSError **)error;
- (void)closeConnection;

/* Run one statement.  Reconnecting and retrying is the caller's business;
   this just tries. */
- (id<CDSQLResult>)runSQL:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error;

/* How many rows the last statement changed. */
- (long long)rowsAffected;

/* Whether the last failure means the connection itself is gone, and how to
   get a new one. */
- (BOOL)connectionIsLost;
- (BOOL)reopenConnectionWithError:(NSError **)error;

@end

/* ------------------------------------------------------------------ */
/* What a backend supplies: the dialect.                              */
/* ------------------------------------------------------------------ */

@interface CDSQLStore (CDSQLDialect)

/* Identifiers */
- (NSUInteger)maximumIdentifierLength;
- (NSString *)schemaConceptName;                     /* "schema" or "database", for messages */

/* Types.  columnTypeForAttribute: is the DDL spelling; introspectedTypeFor:
   is what the database's own catalogue calls it, which is what migration
   compares against. */
- (NSString *)columnTypeForAttributeType:(NSUInteger)attributeType;
- (NSString *)introspectedTypeForColumnType:(NSString *)columnType;
- (NSString *)autoIncrementingPrimaryKeyType;        /* for the history tables */
- (BOOL)columnTypeChangeIsSafeFrom:(NSString *)from to:(NSString *)to;

/* Values */
- (NSString *)likeEscapeClause;                      /* ESCAPE '\', doubled on MySQL */

/* How many bound parameters one statement may carry.  A predicate that
   would need more than this - an IN list of a hundred thousand names - is
   evaluated in memory instead. */
- (NSUInteger)maximumBoundParameters;

/* Comparisons */
- (NSString *)caseInsensitiveLikeClauseForColumn:(NSString *)column placeholder:(NSString *)placeholder;
- (NSString *)caseSensitiveLikeClauseForColumn:(NSString *)column placeholder:(NSString *)placeholder;
- (NSString *)codePointOrderedColumn:(NSString *)column isText:(BOOL)isText;

/* Statements that differ */
- (NSString *)upsertClauseForColumns:(NSArray *)columns keyColumns:(NSArray *)keyColumns;
- (long long)allocatePrimaryKeyForRootEntityID:(long long)entityID error:(NSError **)error;
- (long long)insertHistoryTransactionWithParameters:(NSArray *)parameters error:(NSError **)error;

/* Introspection */
- (NSString *)tableExistsSQL;                        /* $1 is the table name */
- (NSString *)columnsInTableSQL;                     /* $1 is the table; columns: name, type, generated */
- (NSString *)tablesInSchemaSQL;
- (BOOL)introspectedColumnIsGenerated:(NSString *)flag;

/* Migration DDL */
- (NSString *)renameColumnSQLForTable:(NSString *)table from:(NSString *)oldName definition:(NSString *)definition;
- (NSString *)changeColumnTypeSQLForTable:(NSString *)table column:(NSString *)column definition:(NSString *)definition;
- (NSString *)dropTableSQLForTable:(NSString *)table;
- (BOOL)dropSchemaWithError:(NSError **)error;

/* Creating a store: the lock that serializes two clients doing it at once,
   and whether the DDL it runs is transactional (PostgreSQL yes, MySQL no). */
- (BOOL)takeCreationLockWithError:(NSError **)error;
- (void)releaseCreationLock;
- (BOOL)runsDDLInTransactions;

@end

/* ------------------------------------------------------------------ */
/* What a backend supplies: results.                                  */
/* ------------------------------------------------------------------ */

@protocol CDSQLResult <NSObject>
- (NSUInteger)rowCount;
- (BOOL)isNullAtRow:(NSUInteger)row column:(NSUInteger)column;
- (NSString *)stringAtRow:(NSUInteger)row column:(NSUInteger)column;
- (long long)longLongAtRow:(NSUInteger)row column:(NSUInteger)column;
- (double)doubleAtRow:(NSUInteger)row column:(NSUInteger)column;
- (NSData *)dataAtRow:(NSUInteger)row column:(NSUInteger)column;
@end
