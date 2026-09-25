# FreeCoreData

A port of Apple's CoreData for GNUstep. `CoreData/` is the framework,
`Backends/` holds the optional SQL stores, `Tools/momc` compiles models, and
`ModelBuilder/` edits them. The top-level README has the tour.

## GNUstep patches live elsewhere

Fixes to GNUstep itself — libs-base, libs-gui, the Eau theme — are not kept
here. They live in `../gnustep-patches`, which this machine's other GNUstep
projects share, and `.github/scripts/dependencies.sh` clones that repository
at the commit pinned by `GNUSTEP_PATCHES_REF` and applies what it carries.

If a bug here turns out to be GNUstep's, work in that repository and read its
`CLAUDE.md` first: reproduce in the docker container, fix, turn the
reproduction into a test in GNUstep's own suite, and push it there — that is
where patches are kept and where they are sent upstream from. Nothing goes
back into `patches/gnustep/`, which holds only a pointer now.

## Testing

The framework and the backends are tested on GNUstep in docker and on macOS
against Apple's own CoreData, which arbitrates behaviour: a test that is red
on macOS is wrong about Core Data, not a bug in the port.

```sh
make && make -C Tests run-tests                     # framework, on GNUstep
xcodebuild test -project CoreDataTests.xcodeproj \
    -scheme CoreDataTests -destination 'platform=macOS'
```

The SQL backends need a server and skip themselves without one, which is
right on a workstation and wrong in CI — `CD_TEST_REQUIRE_DATABASE` turns
the skip into a failure. See `Backends/README.md`.
