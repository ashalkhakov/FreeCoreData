/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "CDLauncherAppDelegate.h"

@interface CDLauncherAppDelegate ()
@property (nonatomic, strong) NSWindow *window;
@end

@implementation CDLauncherAppDelegate

/* Executable name, button title, one line of explanation. */
- (NSArray *)apps
{
    return @[
        @[ @"ModelBuilder", @"Model Builder",
           @"Create and edit Core Data models (.xcdatamodeld)." ],
        @[ @"Staffbook", @"Staffbook",
           @"Employee roster: bindings, child-context editing, batch requests, async fetches." ],
        @[ @"EmployeeDirectory", @"Employee Directory",
           @"Inheritance, validation, relationships and NSFetchedResultsController, scenario by scenario." ],
    ];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    (void)note;
    [self installMenus];

    NSArray *apps = [self apps];
    CGFloat width = 460, rowHeight = 64, pad = 16;
    NSRect frame = NSMakeRect(0, 0, width,
                              pad * 2 + rowHeight * (CGFloat)[apps count]);
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                            | NSMiniaturizableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"FreeCoreData"];
    NSView *content = [window contentView];

    CGFloat y = NSMaxY(frame) - pad - rowHeight;
    for (NSUInteger i = 0; i < [apps count]; i++) {
        NSButton *button = [[NSButton alloc]
            initWithFrame:NSMakeRect(pad, y + 26, width - pad * 2, 32)];
        [button setTitle:apps[i][1]];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setTag:(NSInteger)i];
        [button setTarget:self];
        [button setAction:@selector(launch:)];
        [content addSubview:button];

        NSTextField *caption = [[NSTextField alloc]
            initWithFrame:NSMakeRect(pad, y + 4, width - pad * 2, 18)];
        [caption setStringValue:apps[i][2]];
        [caption setBezeled:NO];
        [caption setDrawsBackground:NO];
        [caption setEditable:NO];
        [caption setSelectable:NO];
        [caption setFont:[NSFont systemFontOfSize:10]];
        [caption setTextColor:[NSColor darkGrayColor]];
        [content addSubview:caption];

        y -= rowHeight;
    }

    [window center];
    [window makeKeyAndOrderFront:nil];
    self.window = window;
}

- (void)installMenus
{
    NSMenu *menubar = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"FreeCoreData"
                                                     action:NULL
                                              keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"FreeCoreData"];
    [appMenu addItemWithTitle:@"About FreeCoreData"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    [menubar addItem:appItem];
    [NSApp setMainMenu:menubar];
}

/* The chosen app's executable, looked for beside this one.

   Inside the image both live in the same Applications directory, which
   is where a GNUstep application bundle's parent is; the GNUSTEP_*_APPS
   variables cover an installed tree where they do not sit together. */
- (NSString *)executablePathForApp:(NSString *)app
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *siblings = [[[NSBundle mainBundle] bundlePath]
                             stringByDeletingLastPathComponent];
    NSMutableArray *roots = [NSMutableArray arrayWithObject:siblings];
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    for (NSString *key in @[ @"GNUSTEP_LOCAL_APPS", @"GNUSTEP_SYSTEM_APPS" ]) {
        NSString *root = environment[key];
        if ([root length])
            [roots addObject:root];
    }
    for (NSString *root in roots) {
        NSString *path = [root stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%@.app/%@", app, app]];
        if ([files isExecutableFileAtPath:path])
            return path;
    }
    return nil;
}

- (void)launch:(NSButton *)sender
{
    NSArray *apps = [self apps];
    if ([sender tag] < 0 || (NSUInteger)[sender tag] >= [apps count])
        return;

    NSString *app = apps[(NSUInteger)[sender tag]][0];
    NSString *executable = [self executablePathForApp:app];
    if (executable == nil) {
        [self report:@"Application not found"
              detail:[NSString stringWithFormat:
                         @"Could not find %@ beside this launcher.", app]];
        return;
    }

    /* Fire and forget: the launcher is not the app's parent in any
       meaningful sense, and closing it must not take the app along. */
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:executable];
    @try {
        [task launch];
    } @catch (NSException *problem) {
        [self report:@"Could not start the application"
              detail:[NSString stringWithFormat:@"%@: %@", app, [problem reason]]];
    }
}

- (void)report:(NSString *)message detail:(NSString *)detail
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:message];
    [alert setInformativeText:detail];
    [alert runModal];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

@end
