/* Repro for the NSArrayController selection-KVO gap
   (see gnustep-gui-arraycontroller-selection-kvo.patch).

   -[NSArrayController setSelectionIndexes:] changes the selection
   without a word to key-value observers: nothing fires for
   selectionIndexes, selection, selectedObjects, canRemove or
   canSelectNext/Previous.  Every binding that depends on the selection
   therefore freezes at its initial state - a Remove button bound to
   canRemove stays grey forever, a field bound to selection.name keeps
   showing the old row.  -selection itself also answers with the whole
   content array rather than the selected object, so selection.<key>
   reads collect over everything.

   Build and run (against an installed gnustep-gui):

       . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
       clang repro-nsarraycontroller-selection-kvo.m -o repro \
           $(gnustep-config --objc-flags) $(gnustep-config --gui-libs)
       ./repro

   Exit status 0 with the patch applied, 1 without it; each check
   prints its own verdict. */
#import <AppKit/AppKit.h>

static NSMutableSet *fired;

@interface SelectionObserver : NSObject
@end

@implementation SelectionObserver
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    [fired addObject:keyPath];
}
@end

int main(void)
{
    @autoreleasepool {
        int failures = 0;
        fired = [NSMutableSet set];

        NSArrayController *ac = [[NSArrayController alloc] init];
        NSMutableDictionary *ada = [@{ @"name": @"Ada" } mutableCopy];
        NSMutableDictionary *grace = [@{ @"name": @"Grace" } mutableCopy];
        [ac setContent:[NSMutableArray arrayWithObjects:ada, grace, nil]];
        [ac setSelectionIndexes:[NSIndexSet indexSetWithIndex:0]];

        SelectionObserver *observer = [[SelectionObserver alloc] init];
        NSArray *keys = @[ @"selectionIndexes", @"selection",
                           @"selectedObjects", @"canRemove",
                           @"canSelectNext", @"canSelectPrevious",
                           @"selection.name" ];
        NSMutableArray *observed = [NSMutableArray array];
        for (NSString *key in keys) {
            /* Unpatched, observing selection.name THROWS: -selection
               answers with the raw content array, and observing a key
               on an array is unsupported.  Registering must work. */
            @try {
                [ac addObserver:observer forKeyPath:key options:0 context:NULL];
                [observed addObject:key];
            }
            @catch (NSException *problem) {
                printf("%-24s UNOBSERVABLE (%s)\n", [key UTF8String],
                       [[problem name] UTF8String]);
                failures++;
            }
        }

        /* The mutation every table click funnels into. */
        [ac setSelectionIndexes:[NSIndexSet indexSetWithIndex:1]];

        for (NSString *key in observed) {
            BOOL heard = [fired containsObject:key];
            printf("%-24s %s\n", [key UTF8String],
                   heard ? "notified" : "SILENT");
            if (!heard)
                failures++;
        }

        /* And the value itself: with one row selected, selection.<key>
           is that row's value, not a collection over the content. */
        id name = [ac valueForKeyPath:@"selection.name"];
        BOOL right = [name isEqual:@"Grace"];
        printf("%-24s %s (got %s)\n", "selection.name value",
               right ? "correct" : "WRONG",
               [[name description] UTF8String]);
        if (!right)
            failures++;

        for (NSString *key in observed)
            [ac removeObserver:observer forKeyPath:key];

        printf(failures ? "FAIL: %d check(s)\n" : "PASS\n", failures);
        return failures ? 1 : 0;
    }
}
