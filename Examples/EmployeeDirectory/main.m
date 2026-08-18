/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* A small graphical application exercising the CoreData features that
   differ most between implementations: entity inheritance, transient
   properties, validation, to-one/to-many/many-to-many relationships and
   NSFetchedResultsController change tracking, all on top of the SQLite
   store.  It builds and runs unchanged against the GNUstep port (with
   the GNUstep AppKit) and against Apple's CoreData/AppKit on macOS. */
#import <AppKit/AppKit.h>
#import "EDAppDelegate.h"

/* The user interface is created entirely in code (no nib), so the same
   sources work on GNUstep and in Xcode without interface files. */
static void buildMainMenu(NSApplication *application)
{
    NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"Employee Directory"] autorelease];
    NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:@"Employee Directory"
                                              action:NULL
                                              keyEquivalent:@""] autorelease];
    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"Employee Directory"] autorelease];

    [appMenu addItemWithTitle:@"Quit Employee Directory"
             action:@selector(terminate:)
             keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    [mainMenu addItem:appItem];
    [application setMainMenu:mainMenu];
}

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSApplication *application = [NSApplication sharedApplication];
    EDAppDelegate *delegate = [[EDAppDelegate alloc] init];

    /* Make the app a regular, window-owning application even when it is
       started from a bare executable (e.g. straight out of Xcode's build
       directory).  GNUstep does not need (or declare) this. */
#ifdef __APPLE__
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
#endif

    buildMainMenu(application);
    [application setDelegate:delegate];
    [application run];

    [delegate release];
    [pool release];
    return 0;
}
