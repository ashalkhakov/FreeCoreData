# Setting up a modern GNUstep toolchain for this project

This documents the exact steps used to build and test this CoreData port on
Ubuntu 24.04 with the *modern* GNUstep runtime (libobjc2 / gnustep-2.x ABI,
ARC-capable, compiled with clang). The test bundle requires this runtime
(`OBJC_RUNTIME_LIB = ng`, `RUNTIME_VERSION = gnustep-2.0` in
`Tests/GNUmakefile`), so a distro-packaged GNUstep built with GCC and the
old runtime will **not** work.

## 1. Prerequisites

```sh
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build make \
    libxml2-dev libxslt1-dev libffi-dev libicu-dev \
    libgnutls28-dev libcurl4-openssl-dev libavahi-client-dev
export CC=clang CXX=clang++
```

Notes:

- `libgnutls28-dev` and `libxslt1-dev` are required by gnustep-base's
  `configure` (it errors out without TLS support unless you pass
  `--disable-tls`).
- `libdispatch-dev` is not packaged on Ubuntu 24.04; gnustep-corebase is
  therefore configured with `--without-gcd` below.

## 2. Sources

```sh
mkdir gnustep-build && cd gnustep-build
git clone --depth 1 https://github.com/gnustep/libobjc2.git
git clone --depth 1 https://github.com/gnustep/tools-make.git
git clone --depth 1 https://github.com/gnustep/libs-base.git
git clone --depth 1 https://github.com/gnustep/libs-corebase.git
git clone --depth 1 https://github.com/gnustep/tools-xctest.git
```

## 3. libobjc2 (the modern Objective-C runtime)

Install with a plain prefix (`/usr`), **not** `-DGNUSTEP_INSTALL_TYPE=SYSTEM`
— the latter fails with "install FILES given no DESTINATION" when
gnustep-make is not installed yet (chicken-and-egg).

```sh
cmake -S libobjc2 -B libobjc2/build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DTESTS=OFF
ninja -C libobjc2/build
sudo ninja -C libobjc2/build install
sudo ldconfig
```

## 4. gnustep-make, configured for the ng runtime

```sh
cd tools-make
./configure --with-layout=gnustep \
    --enable-native-objc-exceptions \
    --enable-objc-arc \
    --with-library-combo=ng-gnu-gnu
make && sudo make install
cd ..
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
```

`configure` should report `checking for runtime ABI... gnustep-2.x`. The
`ng-gnu-gnu` library combo is what selects libobjc2 + ARC; everything built
by gnustep-make afterwards inherits it.

## 5. gnustep-base (Foundation)

```sh
cd libs-base
./configure
make -j$(nproc)
sudo -E bash -c '. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh; make install'
cd ..
```

## 6. gnustep-corebase (CoreFoundation)

Linked by the test bundle (`-lgnustep-corebase`).

```sh
cd libs-corebase
./configure --without-gcd
make -j$(nproc)
sudo -E bash -c '. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh; make install'
cd ..
```

Caveat found while working on this project: corebase's
`CFUUIDCreateString()` returns corrupted strings on this setup (embedded
spaces / dropped characters), which is why the framework uses Foundation's
`NSUUID` for UUID generation instead of `CFUUIDCreate`.

## 7. tools-xctest (the XCTest framework and `xctest` runner)

```sh
cd tools-xctest
make -j$(nproc)
sudo -E bash -c '. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh; make install'
cd ..
```

## 8. Building and testing this project

```sh
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make                      # builds CoreData.framework
sudo -E bash -c '. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh; make install'
cd Tests
make run-tests            # builds CoreDataTests.bundle and runs it with xctest
```

## General gotchas

- Always source `GNUstep.sh` (from `/usr/GNUstep/System/Library/Makefiles/`
  with the layout above) before invoking `make`, including inside `sudo`
  shells — `sudo make install` alone loses the environment, hence the
  `sudo -E bash -c '. …/GNUstep.sh; make install'` incantation.
- `gnustep-config --variable=GNUSTEP_MAKEFILES` prints the makefiles
  directory if you are unsure where `GNUstep.sh` lives.
- All builds must use clang (`CC=clang CXX=clang++`); GCC cannot compile
  for the gnustep-2.x ABI.
