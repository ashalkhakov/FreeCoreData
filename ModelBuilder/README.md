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

The window layout lives in `MBDocumentWindow.xib`, modeled closely on
Xcode's Core Data editor and loaded by AppKit on macOS and by GSXib5
on GNUstep.  `MBWindowController` adds only behavior: outlet wiring,
target/action, runtime column identifiers, popup population.  Three
panes in a split view, like Xcode's editor:

| Pane | Contents |
|---|---|
| Left | Source list — ENTITIES, FETCH REQUESTS, CONFIGURATIONS — with "+/− Entity" and "+/− Attribute" segmented controls in the bottom bar |
| Center | The selected item's editor: Attributes and Relationships tables in collapsible sections (JUInspectorView) for an entity, "Fetch all" popup and predicate editor (with a T/S source toggle) for a fetch request, membership checklist for a configuration |
| Right | DMTabBar over the data model inspector — one tab per selection kind (entity / fetch request / attribute / relationship) with per-type attribute detail pages, uniqueness constraints, `userInfo` tables and versioning fields |

The vendored `ThirdParty/` controls (DMTabBar, JUInspectorView — both
MIT) supply the Xcode-style inspector chrome.

Version management and validation live in the **Editor** menu (built
programmatically in `main.m`, routed through the responder chain):
**Add Model Version** (duplicates the edited version under the next
free "Model N" name), **Make Current Version** (moves the
`.xccurrentversion` pointer), a **Model Version** submenu for
switching (the edited version is checked, the current one marked),
**Validate Model** (serializes and recompiles through momc, reporting
its errors and warnings) and **Compile to momd**.  The window title
shows the edited version.

Controls whose schema features the serializer does not round-trip yet
(codegen, validation predicates, renaming identifiers, fetch result
types and batch sizes, scalar flags) are disabled with explanatory
tooltips rather than hidden — the layout stays Xcode's.

## What it edits

- Entity name, class, parent, abstract, uniqueness constraints,
  version hash modifier, `userInfo`
- Attribute name, type (including `UUID` and `URI`), optional /
  transient, per-type defaults, derivation expression
  (`uppercase:(title)`, `now()`, key paths — the Derived checkbox
  prompts for it), transformer name and custom class for
  Transformable, version hash modifier, `userInfo`
- Relationship name, destination, inverse, to-one / to-many, ordered,
  delete rule, min / max count, optional / transient, version hash
  modifier, `userInfo`
- Fetch request template name, entity, fetch limit, predicate
- Configuration name and entity membership
- Model versions (add, switch, set current)

Structural changes with graph-wide consequences — deleting an entity,
changing an entity's parent — are applied to the XML and recompiled, so
momc renormalizes relationships, configurations and subentity wiring in
one step and invalid edits are rejected with the compiler's error.

Uniqueness constraints and every other schema feature momc understands
survive open/save untouched even where the editor has no UI for them
yet: the document round-trips through the same serializer the tests
pin down.

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

`MainMenu.xib` and `MBDocumentWindow.xib` are the app's two nibs;
both load through GSXib5.

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
