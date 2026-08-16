# GNUstep-compatible CoreData implementation

A port of the Cocotron CoreData runtime for GNUstep on Linux (and compatible with Apple's CoreData API on macOS).

## Attribution

This project ports sources from the [Cocotron](https://github.com/cjwl/cocotron) project (MIT license).
See [LICENSE](LICENSE) and [LICENSE-Cocotron.txt](LICENSE-Cocotron.txt) for full license text and copyright holders.

## Structure

```
CoreData/          - Framework source (headers + implementation)
Tests/             - Test suite (runs on GNUstep and macOS/Xcode)
GNUmakefile        - Build script for GNUstep (framework.make)
Tests/GNUmakefile  - Build script for the test tool
Tests/XCTestShim.h - Minimal XCTest-compatible shim for GNUstep
```

## Building on GNUstep

```sh
. /usr/share/GNUstep/Makefiles/GNUstep.sh   # source the GNUstep environment
make
sudo make install
```

## Running tests on GNUstep

```sh
cd Tests
make
./obj/CoreDataTests
```

## Running tests on macOS/Xcode

Open the provided Xcode project, select the **CoreDataTests** scheme, and run (`⌘U`). The tests link against Apple's built-in CoreData framework.

## Porting notes

- All sources are compiled with `-fno-objc-arc` (manual reference counting, matching the original Cocotron style).
- Cocotron-specific macros (`NSUnimplementedMethod`, `NSInvalidAbstractInvocation`) are shimmed in `CoreData/CoreDataUtilities.h`.
- `isa` references replaced with `[self class]` / `NSStringFromClass([self class])` for portability.
- `NSXMLDocument` and related Foundation XML classes are used directly (available in GNUstep-base).

