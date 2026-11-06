# Core Data in UDCode

FreeCoreData ships a [UDCode](https://github.com/ashalkhakov/UDCodeKit)
extension, Core Data, for editing Core Data models (`.xcdatamodeld`) and
mapping models (`.xcmappingmodel`) inside UDCode as part of a project. The
editors are Model Builder's: the same source list, pages and inspector.
Model Builder remains its own app, built from the same sources.

## Installing it

Each FreeCoreData release attaches a package for each platform:

| UDCode on | Package |
|---|---|
| macOS, Apple silicon | `coredata-<version>-darwin-arm64.udcx` |
| macOS, Intel | `coredata-<version>-darwin-x64.udcx` |
| Linux (the AppImage), x86_64 | `coredata-<version>-linux-x64.udcx` |
| Linux, aarch64 | `coredata-<version>-linux-arm64.udcx` |
| Windows | `coredata-<version>-win32-x64.udcx` |

Install it with **UDCode > Extensions… > Install from Package…**, or from a
shell with `UDCode --install-extension coredata-<version>-<platform>.udcx`,
then start UDCode again. A package states which UDCode versions it works
with (`engines.udcode` in its `package.json`: 0.19.2 and later 0.19
releases), and UDCode refuses a package built for another version or
another platform.

## Using it

In an Xcode project, a model is a folder (`Model.xcdatamodeld`) holding a
folder per version (`Model.xcdatamodel`), and each version's model is a file
named `contents`. A mapping model is a folder (`Map.xcmappingmodel`) holding
a file named `xcmapping.xml`. Open one of those files from the project
navigator and it shows in its editor, in a tab of its own. A file of either
name that is not a model opens as text, coloured as XML.

The editors' parts spread over UDCode's window the way an Xcode editor's do:

| Part | Where it goes in UDCode |
|---|---|
| The model's entities, fetch requests, configurations and fetch indexes; a mapping model's entity mappings | The tab, on the left |
| The selection's page: an entity's attributes and relationships, a fetch request's predicate, a configuration's entities, an entity mapping's property mappings | The tab, on the right |
| The model's own fields (its version identifier); a mapping model's two models | The inspector pane's first tab after **File** (i) |
| The inspector for what is selected | The inspector pane's next tab (D for a model, M for a mapping) |
| Add Entity, Attribute, Relationship, Fetch Request, Configuration, Fetch Index; Remove Entity; Validate Model; Create NSManagedObject Subclass…; Add and Remove Entity Mapping; Show as Text | The **Editor** menu |

The inspector's fields check what you type before it is stored. A name
another entity or property already has is refused, as are numbers out of
range for an attribute's type, and predicates or expressions that do not
parse. You get an alert saying why, and the field keeps your text for you
to correct.

The model is stored as the document's text: each change you make in the
editor is written back to it. So the things UDCode does for text files work
here too:

- **Undo** and **Redo** are the document's own. Undoing restores the text and
  reads the model again; the selection stays where it still exists.
- **Saving** and the tab's unsaved dot are the document's.
- **Source control** shows what changed. Each change touches only the lines
  that differ.
- **View > Open as Text** shows the XML in a normal editor tab, beside the
  editor. The two tabs are the same document: edits made in the text appear
  in the editor, and the editor's in the text.

A mapping model's editor finds the two models it maps between by the paths
the file records, from where the mapping model is, as Xcode does. When they
cannot be found, or a model's text cannot be read, the tab explains why and
offers to show the file as text.

Versions are files of their own: open the version you want to edit. Making a
version current, adding one and compiling to `.momd` are Model Builder's.

## How it is built

`UDCodeExtension/` contains the extension:

- **`MBUExtension`**, its principal class. It declares two modes in
  `LanguageInfo.plist`, `coredata-model` (files named `contents`) and
  `coredata-mapping` (files named `xcmapping.xml`), both borrowing the XML
  mode's grammar. It gives a document of either mode its editor when the
  text is a model or a mapping model, and adds the Editor menu's items
  (`MBUEditorMenus.xib`).
- **`MBUModelEditorViewController`** and **`MBUMappingEditorViewController`**,
  the tabs (`MBUModelEditor.xib`, `MBUMappingEditor.xib`). Each is an
  `MBModelEditor` or `MBMappingEditor` over the document's text, with no
  undo manager of its own, and Model Builder's parts over that editor. Each
  change the editor reports is written back as one edit of the text
  (`MBUTextEdits`, over UDPieceTable's line diff). A change of the text made
  some other way is read again.
- **`Tests/`**, an XCTest bundle (MBUTests) against UDCode's own document
  and text model.

Model Builder's sources and XIBs (listed once, in `ModelBuilder/files.make`)
are compiled into the bundle. On GNUstep the CoreData framework's library is
carried beside the bundle's binary; on macOS the bundle uses Apple's Core
Data, which is the system's.

It builds on UDCode's SDK, which `.github/pins.env` pins
(`UDCODEKIT_VERSION`). With the SDK installed, `make` builds the extension
and `make check` runs its tests; `make -f Makefile.apple` and its `check` do
the same on macOS, from `.deps/UDCodeKit.xcframework`. `Scripts/udcx.sh
<version> <directory>` packages it, and each release attaches the packages
(`.github/release/udcode.conf`).
