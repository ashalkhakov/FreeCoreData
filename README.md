# GNUstep-compatible CoreData implementation

A port of the Cocotron CoreData runtime for GNUstep on Linux (and compatible with Apple's CoreData API on macOS).

## Attribution

This project ports sources from the [Cocotron](https://github.com/cjwl/cocotron) project (MIT license).
See [LICENSE](LICENSE) and [LICENSE-Cocotron.txt](LICENSE-Cocotron.txt) for full license text and copyright holders.

## Structure

```
CoreData/                        - Framework source (headers + implementation)
Tests/                           - Test suite (runs on GNUstep and macOS/Xcode)
GNUmakefile                      - Build script for GNUstep (framework.make)
Tests/GNUmakefile                - Build script for the XCTest bundle
CoreDataTests.xcodeproj/         - Xcode project for macOS unit tests
```

## Building on GNUstep

Requires gnustep-make and GNUstep-base. The modern runtime (gnustep-2.0 / libobjc2) is recommended.

```sh
. /usr/share/GNUstep/Makefiles/GNUstep.sh   # source the GNUstep environment
make
sudo make install
```

## Running tests on GNUstep

Tests are built as an XCTest bundle and run with the `xctest` runner that ships with GNUstep.

```sh
cd Tests
make run-tests
```

Or, step by step:

```sh
cd Tests
make
. $(gnustep-config --variable=GNUSTEP_MAKEFILES)/GNUstep.sh
xctest CoreDataTests.bundle
```

## Running tests on macOS/Xcode

Open `CoreDataTests.xcodeproj`, select the **CoreDataTests** scheme, and run (`⌘U`).
The tests compile against Apple's built-in CoreData and XCTest frameworks — no custom shim needed.

## Porting notes

- **Framework sources** are compiled with `-fno-objc-arc` (manual reference counting, matching the original Cocotron style). The modern GNUstep runtime (libobjc2) is fully compatible with MRC.
- **Test sources** (`Tests/CoreDataTests.m`) are compiled with ARC (`-fobjc-arc`) and use the real `<XCTest/XCTest.h>` on both GNUstep and macOS.
- Cocotron-specific macros (`NSUnimplementedMethod`, `NSInvalidAbstractInvocation`) are shimmed in `CoreData/CoreDataUtilities.h`.
- `isa` references replaced with `[self class]` / `NSStringFromClass([self class])` for portability.
- `NSXMLDocument` and related Foundation XML classes are used directly (available in GNUstep-base).

