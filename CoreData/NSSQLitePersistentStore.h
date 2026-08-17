/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSIncrementalStore.h>

@class NSMutableDictionary, NSDictionary, NSString, NSURL, NSError;

/* SQLite-backed incremental store (NSSQLiteStoreType).

   The on-disk layout follows the schema used by Apple's SQLite store:

   - Z_METADATA(Z_VERSION, Z_UUID, Z_PLIST) — a single row holding the store
     format version, the store UUID and a binary property list with the rest
     of the store metadata (including the model version hashes used for
     migration/compatibility checks).
   - Z_PRIMARYKEY(Z_ENT, Z_NAME, Z_SUPER, Z_MAX) — one row per entity in the
     model: the entity's numeric ID, its name, the ID of its superentity (0
     for root entities) and the highest primary key handed out so far.
   - One table per root entity named Z<ENTITYNAME> (uppercased), with the
     columns Z_PK (primary key), Z_ENT (entity discriminator for
     subentities), Z_OPT (optimistic-locking version) and one Z<NAME>
     (uppercased) column per attribute and to-one relationship in the
     entity subtree.  To-many relationships with a to-one inverse are
     stored as the foreign key on the destination table; many-to-many
     relationships use a Z_<ENT><NAME> join table.

   Object IDs use Apple's URI form: x-coredata://<UUID>/<Entity>/p<Z_PK>. */
@interface NSSQLitePersistentStore : NSIncrementalStore {
    void *_database;
    NSMutableDictionary *_entityIDs; /* entity name -> NSNumber (Z_ENT) */
    NSMutableDictionary *_entityNamesByID; /* NSNumber (Z_ENT) -> entity name */
}

@end
