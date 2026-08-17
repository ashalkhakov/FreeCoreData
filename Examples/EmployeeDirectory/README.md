# Employee directory example

A small command line program that exercises the CoreData features that differ most
between implementations, on top of the **SQLite store**:

* entity **inheritance** (abstract `Person` with `Employee` and `Contractor` subentities)
* a **transient** property (`Person.fullName`, computed, never written to the store)
* **validation** (mandatory attributes, a validation predicate on `Employee.salary` and a
  custom `-validateSalary:error:` method)
* **to-one** (`Employee.department`), **to-many** (`Department.employees`) and
  **many-to-many** (`Employee.projects` ⟷ `Project.members`) relationships
* `NSFetchedResultsController` change tracking with sections, index paths and a delegate

The managed object model is built in code (`EmployeeDirectoryModel.m`), so the same
sources run against the GNUstep port and against Apple's CoreData without a compiled
`.momd` bundle.

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

## Running on macOS

```sh
cd Examples/EmployeeDirectory
make -f Makefile.macos run
```

The store is created in the temporary directory; pass a path as the first argument to
put it somewhere else.

## Portability notes

* Index paths vended by a fetched results controller carry the section at position 0 and
  the row inside the section at position 1; the example builds them with
  `+[NSIndexPath indexPathWithIndexes:length:]` because the `indexPathForRow:inSection:`
  convenience lives in UIKit/AppKit.
* Transient attributes are read through the accessor implemented by the managed object
  subclass (`-[EDPerson fullName]`) rather than through `-valueForKey:`, because
  `NSManagedObject` reads modeled properties straight from its own storage.
* A to-one relationship is described with `minCount` and `maxCount` both set to one.
