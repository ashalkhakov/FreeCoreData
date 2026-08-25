# ModelBuilder

Document-based AppKit editor for Xcode `.xcdatamodeld` packages — the
GNUstep counterpart of Xcode's Core Data model editor.

The document **is** an `NSManagedObjectModel`. Opening a package runs
the version XML through `CDModelCompiler` (momc's parser); saving runs
the live model back through `CDModelSerializer` (its inverse). The
editor, the compiler and the runtime therefore share one schema
implementation — there is no separate editor-side model, and
`compile(serialize(model))` is covered by the round-trip tests in
`Tests/MomcSerializerTests.m` on both GNUstep and macOS.

Lives at the **FreeCoreData repo root** (`ModelBuilder/`), next to
`Tools/momc` and `coredata-model.make`.

Built for GNUstep (libobjc2 / clang, ARC, GSXib5) and for macOS.

## Layout

Three panes, springs and struts, no Auto Layout:

| Pane | Contents |
|---|---|
| Left | Entities and fetch request templates of the edited version |
| Center | Attributes and relationships of the selected entity, or the fetch predicate |
| Right | Inspector for the selection (entity / attribute / relationship / fetch) plus `userInfo` |

The status row carries the version bar: a popup listing every
`.xcdatamodel` in the package (the ✓ marks the current version),
**+ Version** (Xcode's Add Model Version — duplicates the edited
version under the next free "Model N" name), **Make Current** (moves
the `.xccurrentversion` pointer), and **Validate** (serializes and
recompiles through momc, reporting its errors and warnings).

## What it edits

- Entity name, class, parent, abstract, `userInfo`
- Attribute name, type (including `UUID` and `URI`), optional /
  transient, default, derivation expression (`uppercase:(title)`,
  `now()`, key paths — a non-empty derivation makes the attribute
  derived), `userInfo`
- Relationship name, destination, inverse, to-one / to-many, ordered,
  delete rule, min / max count, `userInfo`
- Fetch request template name, entity, predicate
- Model versions (add, switch, set current)

Structural changes with graph-wide consequences — deleting an entity,
changing an entity's parent — are applied to the XML and recompiled, so
momc renormalizes relationships, configurations and subentity wiring in
one step and invalid edits are rejected with the compiler's error.

Uniqueness constraints, configurations and every other schema feature
momc understands survive open/save untouched even where the editor has
no UI for them yet: the document round-trips through the same
serializer the tests pin down.

## Compiling and decompiling

Validate runs momc in-process. From the command line, the sibling tool
compiles and — new — decompiles:

```
Tools/momc/obj/momc Model.xcdatamodeld Model.momd
Tools/momc/obj/momc --decompile Model.momd Model.xcdatamodeld
```

`--decompile` turns a compiled artifact back into editable source
(every version, `.xccurrentversion` reconstructed), which is how an
existing `.momd` is imported into the editor.

## GNUstep

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
cd ModelBuilder
make
openapp ./ModelBuilder.app
```

`MainMenu.xib` and `MBDocument.xib` load through `GSXib5Loader`.

## macOS

Open `ModelBuilder/ModelBuilder.xcodeproj` and run the **ModelBuilder**
scheme. The app registers `.xcdatamodeld` / `.xcdatamodel` as document
packages and builds against Apple CoreData — the compiler and
serializer sources are portable and are cross-verified against Apple's
classes by the test suite.

## Why this exists

Xcode's model editor is the stock tool on a Mac. On GNUstep there is no
equivalent, and FreeCoreData example models are otherwise edited by
hand (issue #11). ModelBuilder is that editor: same XML Xcode writes,
same three-pane shape as the Xcode designer, with momc as the single
authority on what the XML means.
