# FreeCoreData internals

This document describes how the GNUstep CoreData port works under the
hood: what the major classes are, which data structures carry the
state, and how the big operations (fetch, save, fault, migrate) flow
through them. It is written for developers working on the framework
itself; users of the framework should need nothing beyond Apple's
CoreData documentation, because behaving exactly like Apple's
implementation is the project's goal.

## Goals and method

The port aims to be a drop-in replacement for Apple's CoreData. Where
Apple documents behavior, the port implements the documentation; where
the documentation is silent, the behavior is established empirically by
running the shared test suite (`Tests/`, also buildable as
`CoreDataTests.xcodeproj` against Apple's CoreData on macOS) on a Mac
and encoding what it observes. Tests are written to pass identically on
both platforms; verified divergences are `#if defined(__APPLE__)` /
`#if !defined(__APPLE__)` gated and documented (see "Known divergences"
at the end). The framework proper is compiled with manual reference
counting (`-fno-objc-arc`); the tests build with ARC.

## Layer map

The classes fall into four layers, mirroring Apple's design:

**Model layer** (immutable-after-use description objects):
`NSManagedObjectModel` holds `NSEntityDescription`s; each entity holds
`NSPropertyDescription` subclasses — `NSAttributeDescription` (with
transformable-attribute machinery), `NSDerivedAttributeDescription`
(with the derivation engine), `NSRelationshipDescription`,
`NSFetchedPropertyDescription`, and `NSExpressionDescription` (a
computed column for dictionary fetches). Entities know their
`subentities`/`superentity`, `uniquenessConstraints` and
`compoundIndexes`, and compute per-entity version hashes. Description
objects freeze once a model is used by a coordinator (the
`_hasBeenInstantiated` guard).

**Coordination layer**: `NSPersistentStoreCoordinator` owns the model
and the attached stores. `addPersistentStoreWithType:...` validates the
model for the store type (derived-attribute expression validation
happens here for every store type), checks store/model compatibility
via version hashes in the store metadata, and registers the store.
It also owns object-ID URI translation
(`managedObjectIDForURIRepresentation:`).

**Context layer**: `NSManagedObjectContext` tracks in-memory object
state and implements everything the stores do not: the pending-change
fetch overlay, result shaping, save orchestration, validation calls,
merge policies, delete propagation, and change notifications.
`NSManagedObject` carries per-object state. `NSFetchedResultsController`
sits on top of the context and turns fetch results plus change
notifications into sectioned, delegate-notified table data.

**Store layer**: `NSPersistentStore` is the abstract root with two
families. Atomic stores (`NSAtomicStore` → `NSXMLPersistentStore`,
`NSInMemoryPersistentStore`) load everything into
`NSAtomicStoreCacheNode`s up front and rewrite the file on save.
Incremental stores (`NSIncrementalStore` → `NSSQLitePersistentStore`,
and any third-party subclass such as an OData-backed store) answer
individual requests on demand through `executeRequest:withContext:error:`,
`newValuesForObjectWithID:...` and `newValueForRelationship:...`.

**Migration layer**: `NSMappingModel` (+ `NSEntityMapping`,
`NSPropertyMapping`, `NSEntityMigrationPolicy`) describes a
source→destination transformation; `NSMigrationManager` executes it.
Inferred mapping models cover renames/additions/removals.

## Core data structures

### NSManagedObject

```objc
NSManagedObjectID *_objectID;
NSManagedObjectContext *_context;   // not retained by default
BOOL _isFault;
NSDictionary *_committedValues;     // last-saved snapshot (lazy)
NSMutableDictionary *_changedValues; // unsaved edits, keyed by property
```

An object's visible value for a key is `_changedValues[key]` if present,
else the committed value. `_committedValues` is filled lazily: firing a
row fault asks the object's store (incremental:
`newValuesForObjectWithID:` via an `NSIncrementalStoreNode`; atomic: the
cache node's property cache) and normalizes relationship values —
a to-one is part of the row snapshot — kept as the object ID the node
supplied, or resolved with one `newValueForRelationship:` while the row
fault fires when the node omitted it (Apple-verified behavior); every
to-many is stored as a `CDRelationshipFault` placeholder and costs its
round trip only on first access (matching Apple — no N+1 while
browsing rows), where it is replaced by the resolved IDs and wrapped
for callers in an `NSManagedObjectSet`. `committedValuesForKeys:`
realizes the row fault; with explicit keys it also fires the named
to-many faults, with nil keys unfired to-manys are omitted rather than
fired. `changedValues` is what save writes and what
optimistic locking compares.

### NSManagedObjectContext

```objc
NSMutableSet *_registeredObjects;             // everything known to the context
NSMutableSet *_insertedObjects, *_updatedObjects, *_deletedObjects;
NSMutableSet *_pending*Objects;               // deltas since the last did-change note
NSMapTable *_objectIdToObject;                // uniquing: objectID → object
```

`objectWithID:` uniques through `_objectIdToObject`: one object per ID
per context, created as a fault when unknown. The three change sets are
the whole truth about unsaved state; the fetch overlay, `hasChanges`,
save, and the objects-did-change notification are all derived from
them. `processPendingChanges` drains the `_pending*` sets into an
`NSManagedObjectContextObjectsDidChangeNotification`.

### NSManagedObjectID and reference objects

A permanent object ID is `(entity, store, referenceObject)`; the
reference object is the store's private row identity (the SQLite store
uses the row's `Z_PK` as a number-like string, an incremental store may
use anything). Temporary IDs exist from insertion until
`obtainPermanentIDsForObjects:` / save. The URI form matches Apple
byte-for-byte: `x-coredata://<store-UUID>/<Entity>/p<reference>`, where
the reference is escaped with URL *path* rules and prefixed with one
`p`; decoding strips exactly one `p` and does no percent-decoding
beyond the entity component.

### Snapshots

A "snapshot" is an `NSDictionary` of property→value representing saved
state: `committedValuesForKeys:nil` for objects of incremental stores,
`propertyCache` for atomic cache nodes. Snapshots are what dictionary
results are built from, what optimistic locking compares against, and
what the clean fetch path evaluates predicates on for atomic stores
(saved values, never in-memory edits).

## Fetching: two layers

`executeFetchRequest:error:` implements Apple's documented split — the
store answers with the last-saved state, the context overlays this
context's unsaved changes, then shapes by `resultType`:

1. **Entity resolution.** A request created with
   `+fetchRequestWithEntityName:` resolves the name against the
   coordinator's model here (until then, `-entity` raises
   `NSObjectInaccessibleException`, as on Apple).

2. **Pass-through (clean context).** With nothing pending (or
   `includesPendingChanges` NO, or a dictionary result, which never
   reflects pending changes), a single incremental store gets the
   request as-is and shapes the answer itself. Dictionary requests
   needing grouping/expression/relationship columns are the exception:
   the context fetches objects and shapes rows itself. For atomic
   stores and multi-store unions, membership is computed here by
   evaluating the predicate over cache nodes (saved values), with a
   parallel snapshots array kept for dictionary rows.

3. **Overlay (dirty context).** Store candidates are fetched with the
   predicate but without limit/offset (windows only make sense after
   the merge) and with `includesPendingChanges` cleared on the inner
   request. Then: pending deletes are dropped; pending updates are
   re-tested against the predicate with in-memory values (both
   directions — an update can fall out of or into the result); pending
   inserts that match are appended. `includesSubentities` NO is
   enforced in every pass. Then sort → offset/limit → shape.

4. **Shaping.** Objects, object IDs, `@[@count]`, or dictionary rows.
   `countForFetchRequest:` is a count-typed copy of the request, so it
   inherits the whole pipeline. `_finalizeFetchedObjects:` runs on all
   object-result paths: `returnsObjectsAsFaults` NO realizes faults,
   and `relationshipKeyPathsForPrefetching` is fulfilled by walking the
   key paths (which drives `newValueForRelationship:` during the fetch
   — store-agnostic prefetching that also covers overlay-only rows).

**Dictionary rows** (`_dictionaryResultsForRequest:snapshots:`) support
attribute columns, to-one relationship columns (the row carries the
related object's ID; to-many raises), and `NSExpressionDescription`
columns — plain key-path expressions per row, or aggregates
(`count:`/`sum:`/`min:`/`max:`/`average:` of a key path) per group.
`propertiesToGroupBy` buckets the snapshots (one row per group) and
`havingPredicate` filters rows after grouping, evaluated against a
`CDGroupRow` proxy: column keys answer with row values, any other key
path answers with the array of the group's values, so an aggregate
expression in the predicate computes exactly like SQL `HAVING`. Rows
are windowed after shaping, so grouping, DISTINCT and LIMIT compose as
in SQL.

## Saving

`save:` runs, in order: `processPendingChanges` and delete propagation
(cascade/nullify per relationship delete rules, `validateForDelete:`
honoring Deny); validation (`validateForInsert:`/`Update:` →
`validateValue:forKey:error:` → property constraints plus custom
`validate<Key>:error:` methods, multiple failures combined under
`NSValidationMultipleErrorsError`); conflict detection against the
store's current snapshots with resolution by `_mergePolicy`
(`NSErrorMergePolicy` default, store-trump, object-trump, overwrite,
rollback); recomputation of derived attributes (see below); then one
`NSSaveChangesRequest` (inserted/updated/deleted/locked sets) per
affected store. Incremental stores handle the request in
`executeRequest:`; atomic stores get `updateCacheNode:fromManagedObject:`
/ new cache nodes and a `save:` to rewrite their file. Afterwards
objects' committed values are refreshed, change sets cleared, and
`NSManagedObjectContextDidSaveNotification` posted with the change
sets; `mergeChangesFromContextDidSaveNotification:` applies them to
another context.

## Faulting and relationships

Objects materialize lazily. A registered object with `_isFault` YES has
an ID and nothing else; firing the fault loads the row (see
NSManagedObject above) and calls `awakeFromFetch`. To-one relationships
are satisfied from the row data itself when the store supplied an
object ID in the node (no extra round-trip), and resolved during
row-fault firing when the node omitted them — Apple does the same;
to-many relationships stay relationship faults
(`hasFaultForRelationshipNamed:`) and go through
`newValueForRelationship:` on first access, exactly one round trip
each, after which the answer is cached in the committed values —
as a set of IDs, or an array preserving store order for ordered
relationships, which surface to callers as `NSOrderedSet`s
(`mutableOrderedSetValueForKey:` gives a live mutable view).
`refreshObject:mergeChanges:` turns
an object back into a fault (NO) or re-reads under the current edits
(YES).

## The SQLite store

`NSSQLitePersistentStore` is an incremental store over a schema
mirroring Apple's: one table per entity hierarchy root named `Z<NAME>`,
columns `Z_PK INTEGER PRIMARY KEY`, `Z_ENT` (entity tag, how
subentities share the root table), `Z_OPT` (optimistic-lock version),
one `Z<ATTR>` column per attribute (UUIDs as 16-byte BLOBs, URIs as
their absolute strings), foreign-key columns for to-one relationships,
and separate join tables for many-to-many. Ordered to-manys keep their
positions in hidden `Z_FOK_<REL>` columns — on the destination table
for foreign-key relationships, in the join table for many-to-many
(every join-row write fills both sides' order columns, since either
side's save rewrites the shared rows). Rows are written in two phases
per save — all rows first, then all to-many/order writes — so an owner
saved before its members cannot update rows that do not exist yet. Bookkeeping
tables: `Z_METADATA` (`Z_VERSION`, `Z_UUID`, `Z_PLIST` — the metadata
plist carries store type, UUID and the model's version hashes) and
`Z_PRIMARYKEY` (per-entity `Z_MAX` for primary-key allocation).
Predicates that translate to SQL run in the database; others are
evaluated in memory over fetched rows. Same-table plain-copy derived
attributes become `GENERATED ALWAYS AS (...) STORED` columns (excluded
from INSERT/UPDATE); every other derivation is computed by the shared
engine at save time. String transforms deliberately do not use SQLite's
`UPPER`/`LOWER` (ASCII-only) — Unicode-correct values are computed in
Objective-C and stored.

## The XML and in-memory stores

Both are atomic: all rows live as cache nodes. The XML store reads and
writes Apple's XML store file format (round-trip compatibility is
tested against Apple-generated files, including subentities and
metadata). The in-memory store is the same machinery without a file.

## Derived attributes

`NSDerivedAttributeDescription` carries a store-agnostic derivation
engine (`classifyDerivation` + `_derivedValueForObject:`): plain key
path copies (including cross-relationship paths), string transforms
`uppercase:`/`lowercase:`/`canonical:` (canonical = case- and
diacritic-insensitive fold), to-many aggregates with a terminal
operator (`friends.@count`, `articles.wordCount.@sum`), and `now()`.
Values are recomputed for every dirty object at save time, in the
context, so every store type supports derived attributes (Apple
supports them on SQLite only — a deliberate superset). Expression
validation happens when the store is added; invalid derivations fail
`addPersistentStore` with `NSPersistentStoreOpenError`. A category on
`NSExpression` supplies `_eval_uppercase:` etc. so gnustep-base's
`expressionForFunction:` accepts the derivation function names. (When
constructing function expressions on GNUstep, use colon-less names —
gnustep-base older than 6f47534, 2026-07-30, maps `"canonical:"` to the
selector `_eval_canonical::`.)

## Transformable attributes

`NSAttributeDescription`'s transformable machinery resolves the value
transformer per Apple's rules: an explicit `valueTransformerName`, else
the secure keyed unarchiver default (`NSSecureUnarchiveFromData`;
matching by the "UnarchiveFromData" substring so the real runtime
constants match), transforming on write and reversing on read. Since
values are compared by the snapshot machinery, mutating a transformable
value in place and re-setting an equal object is not detected as a
change — verified Apple behavior ("snapshot poisoning") that the port
reproduces.

## Versioning and migration

Each entity's version hash digests its structure (properties, types,
constraints when present, derivation expressions, version hash
modifier); the model's hashes are stamped into store metadata on save
and compared on open — an incompatible model fails with the migration
error unless `NSIgnorePersistentStoreVersioningOption` is set.
`NSMappingModel inferredMappingModelForSourceModel:destinationModel:`
matches entities/attributes by name and hash; `NSMigrationManager`
walks the mapping, copies rows source→destination through the entity
migration policies, and swaps the store.

## The model compiler (momc)

`Tools/momc` is the port's equivalent of Apple's model compiler: it
parses Xcode's `.xcdatamodeld`/`.xcdatamodel` source format
(`contents` XML plus `.xccurrentversion`) with NSXMLDocument, builds
an `NSManagedObjectModel` using the framework's own description
classes, and writes the keyed-archive `.mom`/`.momd` form the runtime
loads — every version compiled, the current version and per-version
entity hashes recorded in `VersionInfo.plist`. It covers the port's
whole feature set: derived attributes (constructed colon-safely for
old gnustep-base), transformables, UUID/URI attribute types, ordered
relationships, subentities, constraints, configurations, and fetch
request templates. Other projects consume it through `coredata-model.make`
(installed into `$(GNUSTEP_MAKEFILES)` by `make install` in
Tools/momc): setting `<target>_XCDATAMODELD_FILES` compiles the models
and adds the `.momd` to the target's resources; models are recompiled
on every build (model directories don't change mtime when edited
inside, and Xcode's space-containing version names cannot ride in make
prerequisites). The test suite dogfoods the fragment: Apple's momc and
the port's momc compile the identical `MomcFixture.xcdatamodeld`, and
`MomcCompiledModelTests` asserts both produced the same model.

## Build and tests

The framework builds with gnustep-make (`GNUmakefile`,
`FRAMEWORK_NAME = CoreData`); the ng runtime and gnustep-2.0 ABI are
required (`libobjc2`). `Tests/GNUmakefile` links the test bundle
against the *uninstalled* framework in the source tree and `run-tests`
rebuilds the framework first, so tests never depend on an installed
copy. The same test sources build in `CoreDataTests.xcodeproj` against
Apple's CoreData; a behavior is only considered "Apple behavior" once
that suite has passed on a Mac. XCTest on GNUstep comes from
tools-xctest.

## Known divergences from Apple (all deliberate, all documented in tests)

- Derived attributes work on every store type; Apple's atomic stores
  refuse them.
- Fetched objects are realized during the fetch, so default
  `returnsObjectsAsFaults` YES fault-ness is not observable; the NO
  path behaves identically to Apple.
- With pending changes, `fetchLimit`/`fetchOffset` window the *merged*
  result (Apple windows in the store and re-merges — behavior Apple
  documents as unreliable).
- ID fetches are fully sorted; Apple does not reliably sort the
  overlay-only portion.
- `havingPredicate` over attribute-grouped dictionary fetches works
  (both the SQL-style aggregate-expression form and the alias form);
  Apple rejects both spellings.
- A to-many relationship in `propertiesToFetch` raises cleanly in both
  string and description form; Apple crashes on the string form.
- Objects show their saved values immediately after a save without an
  explicit refresh.
