# GNUstep-compatible CoreData implementation

A port of the Cocotron CoreData runtime for GNUstep on Linux (and compatible with Apple's CoreData API on macOS).

## Attribution

This project ports sources from the [Cocotron](https://github.com/cjwl/cocotron) project (MIT license).
See [LICENSE](LICENSE) and [LICENSE-Cocotron.txt](LICENSE-Cocotron.txt) for full license text and copyright holders.

`NSFetchedResultsController` follows the change tracking approach of
[MRTFetchedResultsController](https://github.com/matteorattotti/MRTFetchedResultsController)
by Matteo Rattotti (MIT license), extended with the sectioning and index path based API of
Apple's `NSFetchedResultsController`.

## Structure

```
CoreData/                        - Framework source (headers + implementation)
Tests/                           - Test suite (runs on GNUstep and macOS/Xcode)
Backends/                        - Optional SQL stores (PostgreSQL, MySQL/MariaDB)
Examples/EmployeeDirectory/      - SQLite store, shown through AppKit
Examples/Staffbook/              - NSPersistentContainer, bindings and XIBs
Examples/Bulletin/               - Persistent history: two stacks, one store
ModelBuilder/                    - Document-based .xcdatamodeld editor (AppKit)
CDLauncher/                      - App chooser inside the Linux AppImage
Tools/momc/                      - Xcode model compiler (.xcdatamodeld → .momd)
coredata-model.make              - gnustep-make fragment for XCDATAMODELD_FILES
GNUmakefile                      - Build script for GNUstep (framework.make)
Tests/GNUmakefile                - Build script for the XCTest bundle
CoreDataTests.xcodeproj/         - Xcode project for macOS unit tests
```

## Building on GNUstep

Requires gnustep-make and GNUstep-base. The modern runtime (gnustep-2.0 / libobjc2) is recommended.
See [docs/GNUSTEP-SETUP.md](docs/GNUSTEP-SETUP.md) for step-by-step instructions on building the
full modern toolchain (libobjc2, gnustep-make, gnustep-base, tools-xctest) from source.

```sh
. /usr/share/GNUstep/Makefiles/GNUstep.sh   # source the GNUstep environment
make
sudo make install
```

## Running tests on GNUstep

Tests are built as an XCTest bundle and run with the `xctest` runner that ships with GNUstep.

```sh
cd Tests
make run-tests
```

Or, step by step:

```sh
cd Tests
make
. $(gnustep-config --variable=GNUSTEP_MAKEFILES)/GNUstep.sh
xctest CoreDataTests.bundle
```

## Running tests on macOS/Xcode

Open `CoreDataTests.xcodeproj`, select the **CoreDataTests** scheme, and run (`⌘U`).
The tests compile against Apple's built-in CoreData and XCTest frameworks — no custom shim needed.

## SQL backends

The framework ships an in-memory, an XML/binary and a SQLite store.  For a
database on the other end of a network, `Backends/` adds two more: PostgreSQL
and MySQL/MariaDB.  They are an addon - nothing there is built by the
top-level `make`, nothing is linked into `CoreData.framework`, and neither
adds a dependency for anyone who only wants the framework.

Both keep the same schema the SQLite store does (`Z_PK`, `Z_ENT`, join tables
and all), and both are written against public Core Data API only, so the same
sources build and run against Apple's CoreData on macOS - which is how their
behaviour is arbitrated.  They support fetching and saving, faulting,
relationships, batch insert/update/delete, optimistic locking with merge
conflicts, in-place schema migration, and persistent history (that last one
on this framework only, which publishes the API a store needs for it).
Predicates, sorting, grouping and aggregates are translated to SQL where they
can be, and evaluated in memory where they cannot.

```sh
make                              # the framework first
make -C Backends/PostgreSQL       # then the backend (needs libpq)
```

```objc
#import <CDPostgreSQLStore/CDPostgreSQLStore.h>

[coordinator addPersistentStoreWithType:CDPostgreSQLStoreType
                          configuration:nil
                                    URL:[NSURL URLWithString:@"postgresql://localhost/mydb"]
                                options:nil
                                  error:&error];
```

Linking the library is all an application has to do: each store registers
itself from `+load`.  Their test suites need a server and are skipped without
one; CI runs them against PostgreSQL 16, MySQL 8 and MariaDB 11.  See
[Backends/README.md](Backends/README.md).

## Example applications

Three graphical (AppKit) samples, each aimed at a different part of the
framework.  All three build against this port on GNUstep and, through their
bundled Xcode projects, against Apple's CoreData on macOS - so anything one of
them shows can be compared with the implementation this is a port of.

![GNUstep on Linux with Eau theme](Screenshots/EmployeeDirectory-Linux.png)
![Mac](Screenshots/EmployeeDirectory-Mac.png)

**[Employee directory](Examples/EmployeeDirectory/README.md)** - the features
that differ most between implementations, on the SQLite store: entity
inheritance, a transient property, validation, to-one/to-many/many-to-many
relationships and `NSFetchedResultsController`, with one button per scenario.

**[Staffbook](Examples/Staffbook/README.md)** - the modern API surface in plain
ARC Objective-C: `NSPersistentContainer` stands up the stack, and the roster is
an `NSArrayController` wired up in a XIB with Cocoa bindings.

**[Bulletin](Examples/Bulletin/README.md)** - persistent history, by running two
complete Core Data stacks over one store file in a single process, each with its
own window and `transactionAuthor`.  A save in one window is invisible to the
other until it notices the transaction and merges it, which is what an
app-plus-extension setup looks like from the inside.

## Model editor

![ModelBuilder on GNUstep/Linux with the Eau theme](Screenshots/ModelBuilder-Linux.png)

`ModelBuilder/` is a document-based AppKit editor for Xcode `.xcdatamodeld`
packages (current version only). It lives at the repo root next to `Tools/momc`
and `coredata-model.make`. Edit a model, then compile it:

```sh
make -C Tools/momc
Tools/momc/obj/momc Examples/EmployeeDirectory/EmployeeDirectory.xcdatamodeld /tmp/EmployeeDirectory.momd
```

See [ModelBuilder/README.md](ModelBuilder/README.md).

Tagged releases (`v*`) publish ModelBuilder for both platforms: a Linux
AppImage with the GNUstep stack inside it, and a signed, notarized macOS app
(universal, built on Cocoa and the system CoreData). Every CI run also uploads
an unsigned build of each as a workflow artifact. See
[.github/workflows/](.github/workflows/).

The AppImage carries the three samples as well, behind a launcher: run it with
no arguments to choose, or name one directly.

```sh
./FreeCoreData-Linux-*.AppImage staffbook      # or employeedirectory, bulletin
./FreeCoreData-Linux-*.AppImage MyModel.xcdatamodeld   # a path opens the editor
```

## Porting notes

- **Framework sources** are compiled with `-fno-objc-arc` (manual reference counting, matching the original Cocotron style). The modern GNUstep runtime (libobjc2) is fully compatible with MRC.
- **Test sources** (`Tests/CoreDataTests.m`) are compiled with ARC (`-fobjc-arc`) and use the real `<XCTest/XCTest.h>` on both GNUstep and macOS.
- Cocotron-specific macros (`NSUnimplementedMethod`, `NSInvalidAbstractInvocation`) are shimmed in `CoreData/CoreDataUtilities.h`.
- `isa` references replaced with `[self class]` / `NSStringFromClass([self class])` for portability.
- `NSXMLDocument` and related Foundation XML classes are used directly (available in GNUstep-base).
- `NSFetchedResultsController` index paths hold the section at position 0 and the row inside the
  section at position 1, matching Apple; build them with
  `+[NSIndexPath indexPathWithIndexes:length:]` since `indexPathForRow:inSection:` lives in
  UIKit/AppKit.  Section information caching (the `cacheName` argument) is not implemented.
- `-[NSRelationshipDescription isToMany]` matches Apple: a relationship is to-one exactly when
  `maxCount` is one (a `maxCount` of zero means unbounded, i.e. to-many); `minCount` only
  expresses whether the relationship is mandatory.
- `-[NSManagedObject valueForKey:]` dispatches to a custom accessor implemented by the
  subclass (e.g. a computed transient property) before falling back to the modeled storage,
  matching Apple's key-value coding behavior.
- When both AppKit and CoreData are imported on GNUstep, import AppKit first: GNUstep's AppKit
  duplicates the `NSAttributeType` constants in `NSPredicateEditorRowTemplate.h`, and the
  CoreData headers step aside when that header was already included.
