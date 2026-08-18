# Employee directory example

A small **graphical** (AppKit) application that exercises the CoreData features that
differ most between implementations, on top of the **SQLite store**:

* entity **inheritance** (abstract `Person` with `Employee` and `Contractor` subentities)
* a **transient** property (`Person.fullName`, computed by a custom accessor, never
  written to the store, and read through plain `-valueForKey:`)
* **validation** (mandatory attributes, a validation predicate on `Employee.salary` and a
  custom `-validateSalary:error:` method)
* **to-one** (`Employee.department`), **to-many** (`Department.employees`) and
  **many-to-many** (`Employee.projects` ⟷ `Project.members`) relationships
* `NSFetchedResultsController` change tracking with sections, index paths and a delegate

The window shows the employee table (grouped into department sections by the fetched
results controller) next to a log of every delegate callback, and one button per usage
scenario so each can be run and verified interactively:

| Button | Scenario |
| --- | --- |
| Add Employee | insert a new object, to-one relationship, FRC insert events |
| Move Department | reassign a to-one relationship, FRC move events across sections |
| Give Raise | update an attribute, FRC update events |
| Delete Employee | delete an object, FRC delete events |
| Validation Demo | rejected saves (missing value, predicate, custom validator), then an accepted one |
| Save | persist the context to the SQLite store |
| Reload From Store | reopen the store in a fresh context and refetch |
| List People | fetch the abstract `Person` entity (inheritance, transient `fullName`) |
| List Projects | walk the many-to-many relationship |

The managed object model is designed the usual CoreData way: its source lives in
`EmployeeDirectory.xcdatamodeld` (edited with Xcode's data model editor on a Mac —
porting a designer application is a separate project) and the compiled
`EmployeeDirectory.momd` is kept in source control. At runtime the application loads
the `.momd` from its bundle (`EmployeeDirectoryModel.m`), which works identically on
the GNUstep port and on Apple's CoreData. The user interface is built in code (no
nib), so the very same sources run against both implementations.

On macOS, Xcode compiles the `.xcdatamodeld` into the application bundle itself; the
committed `.momd` is what the GNUstep build copies into the app wrapper as a resource.
After editing the model on a Mac, recompile it and refresh the committed bundle with

```sh
xcrun momc EmployeeDirectory.xcdatamodeld EmployeeDirectory.momd
```

## Running on GNUstep

Build and install the framework first (from the top of the repository):

```sh
. /usr/share/GNUstep/Makefiles/GNUstep.sh
make
sudo make install
```

then

```sh
cd Examples/EmployeeDirectory
make
make run
```

## Running on macOS (Xcode)

Open `EmployeeDirectory.xcodeproj` and press Run, or build from the command line:

```sh
cd Examples/EmployeeDirectory
xcodebuild -project EmployeeDirectory.xcodeproj -scheme EmployeeDirectory build
```

The store is created in the temporary directory; its exact path is printed at the top
of the log pane.

## Portability notes

* Validation predicates are stored in a GNUstep-produced `.mom` as predicate format
  strings, because gnustep-base's `NSPredicate` does not support archiving yet; the
  CoreData port accepts both archived `NSPredicate` objects and format strings when
  loading a model. The salary rule is expressed as `NOT (SELF < 0)` (i.e. `>= 0`)
  since that form round-trips exactly through `-predicateFormat` on GNUstep.

* Index paths vended by a fetched results controller carry the section at position 0 and
  the row inside the section at position 1; the example builds them with
  `+[NSIndexPath indexPathWithIndexes:length:]` because the `indexPathForRow:inSection:`
  convenience lives in UIKit/AppKit.
* A to-one relationship is described by a `maxCount` of one (a `maxCount` of zero means
  unbounded, i.e. to-many); `minCount`/`optional` only express whether it is mandatory.
* When both AppKit and CoreData are used on GNUstep, import AppKit before CoreData:
  GNUstep's AppKit duplicates the `NSAttributeType` constants in
  `NSPredicateEditorRowTemplate.h`, and the CoreData headers step aside when that
  header was included first.
