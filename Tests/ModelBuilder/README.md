# ModelBuilder's tests

One XCTest bundle, **ModelBuilderTests**, holding ModelBuilder's sources
and XIBs. Each test opens a fresh document and checks one behaviour.

| Suite | What it covers |
|---|---|
| `MBDocumentTests` | the model document and its `MBModelEditor`, with no window: opening a package, what round-trips through the serializer and momc, validation, versions, configurations, reparenting, save, compile, and undo of every kind of edit |
| `MBEditorsTests` | the inspector's view models (`MBEditors`): key-value validation (names, numbers in range, patterns, predicates, parents), `-reload`, staying valid when the model is replaced, the date and string defaults' ticks, and the change notices (one per edit, the selection's after it) |
| `MBModelWindowTests` | the model window loaded from its XIBs: the parts' outlets, the inspector's bound fields (types, defaults, renaming, scalar, validation, external storage, codegen, fetch templates, the Identifier), the stepper fields, the centre's popup columns, the implicit Default configuration, and fetch indexes |
| `MBMappingEditorTests` | the mapping editor and its view models, with no window: the mapping Xcode made (`Tests/MappingFixture.xcmappingmodel`) read from its text, its rows (reading them changes nothing), edits, undo, validation, and the text written back |
| `MBMappingWindowTests` | the mapping window loaded from its XIBs, driven as a user would, and the New Mapping Model panel |

A window test edits as a user does: it changes a control and sends the
control's action, which is what hands a bound control's value to the
editor it is bound to.

## Running

On GNUstep, after `make` at the repository's root (the tests link the
CoreData framework built there):

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
make -C Tests/ModelBuilder
xvfb-run -a make -C Tests/ModelBuilder check
```

The windows need a display: the root GNUmakefile's `check` runs the
bundle under `xvfb-run` when there is none, as CI does. `check` runs
`xctest` with the library path pinned to the framework built in the
tree, gives it ten minutes, and prints the end of what it wrote
(`ModelBuilderTests.log`).

On macOS, `make -f Makefile.apple check` runs the same suites in
ModelBuilder.xcodeproj's ModelBuilderTests target.

Compiling the app's sources from here makes gnustep-make mirror their
`../../` paths into `ModelBuilder/` and `Tools/` directories beside
`obj/`; `make clean` sweeps them.
