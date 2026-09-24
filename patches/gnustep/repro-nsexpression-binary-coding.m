/* Repro for the unarchivable binary expressions
   (see gnustep-base-expression-binary-coding.patch).

   Four kinds of NSExpression in gnustep-base share the class that holds
   a left and a right expression: a key path composition ($x.y, and
   anything else written with a dot after something that is not a plain
   key path), a union, an intersection and a difference.  None of them
   implements -encodeWithCoder:, so they inherit NSExpression's, which
   raises "should be overridden by subclass".

   Archiving a predicate is how a Core Data model stores a fetch request
   template and how one process hands a predicate to another, so a
   predicate with $x.y in it cannot be saved at all.

   With the patch the four encode and decode their two halves, writing
   out which kind they are so that one initialiser can read them all
   back.

   Build and run (against an installed gnustep-base):

       . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
       clang repro-nsexpression-binary-coding.m -o repro \
           $(gnustep-config --objc-flags) $(gnustep-config --base-libs)
       ./repro

   Exit status 0 with the patch applied, 1 without it. */
#import <Foundation/Foundation.h>

static int failures = 0;

static void
roundTrip(const char *what, NSExpression *expression)
{
    @try
    {
        NSData	     *archived;
        NSExpression *back;

        archived = [NSKeyedArchiver archivedDataWithRootObject: expression];
        back = [NSKeyedUnarchiver unarchiveObjectWithData: archived];

        if (![back isEqual: expression])
        {
            NSLog(@"FAIL %s: came back as %@, not %@", what, back, expression);
            failures++;
            return;
        }
        if ([back expressionType] != [expression expressionType])
        {
            NSLog(@"FAIL %s: came back as type %lu, not %lu", what,
                  (unsigned long)[back expressionType],
                  (unsigned long)[expression expressionType]);
            failures++;
            return;
        }
        NSLog(@"ok   %s (%lu bytes)", what, (unsigned long)[archived length]);
    }
    @catch (NSException *exception)
    {
        NSLog(@"FAIL %s: %@ -- %@", what, [exception name], [exception reason]);
        failures++;
    }
}

int
main(void)
{
    @autoreleasepool
    {
        NSExpression *left = [NSExpression expressionForVariable: @"x"];
        NSExpression *right = [NSExpression expressionForKeyPath: @"age"];
        NSExpression *set = [NSExpression expressionForKeyPath: @"friends"];
        NSExpression *other = [NSExpression expressionForKeyPath: @"colleagues"];

        roundTrip("key path composition ($x.age)",
                  [NSExpression expressionForKeyPathCompositionWithLeft: left
                                                                  right: right]);
        roundTrip("union", [NSExpression expressionForUnionSet: set with: other]);
        roundTrip("intersection",
                  [NSExpression expressionForIntersectSet: set with: other]);
        roundTrip("difference",
                  [NSExpression expressionForMinusSet: set with: other]);

        /* The whole point: a predicate that contains one of them. */
        @try
        {
            NSPredicate *predicate;
            NSPredicate *back;

            predicate = [NSPredicate predicateWithFormat: @"$x.age > %d", 40];
            back = [NSKeyedUnarchiver unarchiveObjectWithData:
                [NSKeyedArchiver archivedDataWithRootObject: predicate]];

            if (![[back predicateFormat] isEqual: [predicate predicateFormat]])
            {
                NSLog(@"FAIL predicate: %@ came back as %@",
                      [predicate predicateFormat], [back predicateFormat]);
                failures++;
            }
            else
            {
                NSLog(@"ok   predicate (%@)", [back predicateFormat]);
            }
        }
        @catch (NSException *exception)
        {
            NSLog(@"FAIL predicate: %@ -- %@",
                  [exception name], [exception reason]);
            failures++;
        }
    }

    NSLog(@"%s", failures == 0 ? "PASS" : "FAIL");

    return (failures == 0) ? 0 : 1;
}
