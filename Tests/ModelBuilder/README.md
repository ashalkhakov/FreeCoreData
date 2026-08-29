# ModelBuilder end-to-end tests

Two headless test binaries for the ModelBuilder app, written as
**textual use-cases**: every group of checks sits under a
`SCENARIO(...)` with Given/When/Then prose, deliberately
gherkin-shaped so the catalogue can be ported to a BDD runner when
GNUstep grows one.  Until then, the binaries are the runner: they
print one `Scenario:` header per use-case, `ok`/`FAIL` per check, and
exit non-zero on any failure.

## The two suites

**MBDocumentSmoke** — the document layer, no window, no display.

| Scenario | Covers |
|---|---|
| Opening a .xcdatamodeld package | read path, versions, configurations |
| Property-level version hash modifiers round-trip | serializer/compiler extension + constraints |
| Validation runs momc's checks in-process | `validateModel:` |
| Model versions: add, make current, switch | the Xcode Editor-menu semantics |
| Configurations: add, membership, rename, remove | the CDModelMutator XML path |
| Renaming IDs, fetch features, scalar flags and validation round-trip | elementID/renamingIdentifier, fetch resultType/batch/flags, usesScalarValueType, validation predicates — serializer spellings + recompile |
| Reparenting an entity is graph surgery | mutator + momc renormalization |
| Saving and reopening preserves everything | write/read round trip |
| Compile to momd produces a loadable artifact | in-process momc |

**MBWindowProbe** — the real window: loads `MBDocumentWindow.xib`
through `MBWindowController` on the headless backend and drives the
actual controls (row selection, popup changes, target/action
dispatch, cell-based table edits).

| Scenario | Covers |
|---|---|
| Opening a model document loads the window from the nib | nib loading, outlets, vocabulary popups |
| Selecting attributes shows the matching per-type detail page | selection routing, inspector fill |
| Changing an attribute's type from the inspector popup | apply path, default dropping, page switch, xib action wiring |
| Collapsible sections are adopted from the nib | vendored JUInspectorView `awakeFromNib` support, IB runtime attributes |
| A type flip through Transformable leaves no transformer residue | the Apple `setValueTransformerName:nil` crash class |
| Center-pane combo columns list and apply their choices | NSComboBoxCell columns: Type / Destination / Inverse |
| The xib's delete-rule items match momc's vocabulary | IB-authored items pinned against `CDModelCompiler` |
| Renaming, scalar, validation and fetch-template controls are live | inspector enablement + fill/apply for the newly round-tripped features |
| The Codegen popup is live and round-trips codeGenerationType | codegen metadata: popup ↔ compiler carry ↔ serialized XML |
| Stepper text fields own and drive their steppers | MBStepperTextField: self-created stepper, apply through the field's action, enablement mirroring |

## Requirements

- gnustep-back built with `--enable-server=headless
  --enable-graphics=headless` (no display or X11 needed).
- libs-base carrying
  `patches/gnustep-base-nsxmlnode-detached-attribute-dict-strings.patch`
  (repo root `patches/`) — without it, the structural-surgery
  scenarios crash in NSXML.
- The built CoreData framework in the source tree (`make` at the repo
  root first).

## Running

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
cd Tests/ModelBuilder
make && make check
```

`make check` runs both binaries with the library path pinned to the
build-tree framework, the same way `Tests/GNUmakefile` runs the XCTest
bundle.  MBWindowProbe runs from an `.app`-shaped wrapper assembled at
build time (`obj/MBWindowProbe.app/Resources/MBDocumentWindow.xib`) -
GNUstep's NSBundle resolves a `Resources/` subdirectory only for
app-wrapper paths - so a rebuilt xib is picked up by rebuilding.

Two build-artifact notes: compiling the app's sources from here makes
gnustep-make mirror their `../../` paths into `ModelBuilder/` and
`Tools/` directories beside `obj/` (swept by `make clean`; worth a
`.gitignore` entry alongside `obj/`).

On macOS these are not needed: the same ground is covered by running
the app and the XCTest suite; the probe exists precisely to exercise
the GUI code paths that a display-less GNUstep CI can reach.
