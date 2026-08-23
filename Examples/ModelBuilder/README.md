# ModelBuilder

Document-based AppKit editor for Xcode `.xcdatamodeld` packages. It opens
the **current version** (`.xccurrentversion` → `Version.xcdatamodel/contents`)
and writes that same XML back so Xcode, FreeCoreData consumers, and
`ODataIncrementalStore`'s Catalog model stay interchangeable.

Built for GNUstep (libobjc2 / clang, ARC, GSXib5) and for macOS.

## Layout

Three panes, springs and struts, no Auto Layout:

| Pane | Contents |
|---|---|
| Left | Entities and fetch requests in the current version |
| Center | Attributes and relationships of the selected entity, or the fetch predicate |
| Right | Inspector for the selection (entity / attribute / relationship / fetch) plus `userInfo` |

The document **is** the `.xcdatamodeld` wrapper. Other versions in the
package are preserved on save; only the current `contents` file and
`.xccurrentversion` are rewritten. A bare `.xcdatamodel` directory is
accepted on open.

## What it edits

- Entity name, class, parent, abstract, syncable, `userInfo`
- Attribute name, Xcode type (`Integer 32`, `Decimal`, `String`, …), optional / transient, default, min / max, `userInfo`
- Relationship name, destination, inverse, to-one / to-many, delete rule, min / max count, `userInfo`
- Fetch request name, entity, predicate string

A new document starts with one `Entity`. File → Open a Catalog or
EmployeeDirectory `.xcdatamodeld` to see a full model.

## GNUstep

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
make
openapp ./ModelBuilder.app
```

`MainMenu.xib` and `MBDocument.xib` load through `GSXib5Loader`.

## macOS

Open `ModelBuilder.xcodeproj` and run the **ModelBuilder** scheme. The
app registers `.xcdatamodeld` / `.xcdatamodel` as document packages.

## Why this exists

Xcode's model editor is the stock tool on a Mac. On GNUstep there is no
equivalent, and FreeCoreData example models are otherwise edited by
hand. ModelBuilder is that editor: same XML Xcode writes, same three-pane
shape as the Xcode designer.
