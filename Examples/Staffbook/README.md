# Staffbook

A small employee roster whose entire point is to exercise FreeCoreData's
modern API surface, one feature per place.  It is plain modern
Objective-C with ARC, XIBs, and Cocoa bindings, and the same sources
build against Apple's CoreData on macOS and against FreeCoreData on
GNUstep.

| Feature | Where |
| --- | --- |
| `NSPersistentContainer` | `SBAppDelegate` stands up the whole stack in two calls |
| List, filtering, sorting | `SBEmployeeWindowController` - one `NSArrayController` declared in `EmployeeWindow.xib` with the bindings (columns to `arrangedObjects`, table content/selection/sort descriptors, button enabling to `canRemove`); code only feeds it content |
| Parent/child contexts | `SBEmployeeEditorController` - the editor is a child context; Save is one child save + one parent save, Cancel discards everything |
| Application transaction | Reviews added under an employee in the editor ride in the same child save - they reach the parent and the store together with the employee, or not at all |
| `NSBatchInsertRequest` | Insert Sample Data (the dictionary-handler flavor) |
| `NSBatchUpdateRequest` | Move Shown - the table's filter predicate *is* the request's predicate |
| `NSBatchDeleteRequest` | Delete Shown |
| `mergeChangesFromRemoteContextSave:intoContexts:` | after every batch action, so the bypassed viewContext catches up |
| `NSAsynchronousFetchRequest` | the department chart: the fetch runs as its own event on the viewContext's queue and the completion block redraws |

## Building

On GNUstep, with the framework and `momc` installed (both come from this
repository's root `make install`):

    . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh   # or your prefix
    make

`MOMC=/path/to/momc make` points the model compiler somewhere else, for
example at a freshly built, uninstalled `Tools/momc/obj/momc`.

The selection-dependent bindings (Edit/Delete/Remove enabling, the
review-date picker) need the gnustep-gui carried in this repository's
CI stack: stock gnustep-gui is missing the selection-KVO fix in
`patches/gnustep/gnustep-gui-arraycontroller-selection-kvo.patch`
(a repro sits beside it).

On macOS, open `Staffbook.xcodeproj` and run the **Staffbook** scheme,
or build it from the command line:

    xcodebuild -project Staffbook.xcodeproj -scheme Staffbook build

It builds the same sources, the three XIBs and `Staffbook.xcdatamodeld`
against Apple's CoreData (Xcode compiles the model itself), with
`Staffbook-Info.plist` as the bundle's Info.plist.  Codegen for the two
entities stays off because `SBManagedObjects.[hm]` is written by hand.
`SBGNUstepCompat.h` is force-included only by the GNUstep build and is
never seen by Xcode.
