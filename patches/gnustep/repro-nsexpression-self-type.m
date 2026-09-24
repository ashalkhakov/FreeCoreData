/* Repro for the SELF expression's type
   (see gnustep-base-expression-self-type.patch).

   Every kind of NSExpression in gnustep-base is built through
   -initWithExpressionType:, which is what -expressionType answers with -
   every kind but one.  The shared expression behind
   +expressionForEvaluatedObject is built with +new, so its type stays
   zero, and zero is NSConstantValueExpressionType.

   SELF therefore reports itself as a constant value.  Code that
   switches on -expressionType - a persistent store translating a
   predicate, say - either mistakes SELF for a constant and asks it for
   a constantValue it has not got, or silently declines to translate
   something it does understand.

   With the patch the shared expression is built with its own type, like
   all the others.

   Build and run (against an installed gnustep-base):

       . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
       clang repro-nsexpression-self-type.m -o repro \
           $(gnustep-config --objc-flags) $(gnustep-config --base-libs)
       ./repro

   Exit status 0 with the patch applied, 1 without it. */
#import <Foundation/Foundation.h>

int
main(void)
{
    int failures = 0;

    @autoreleasepool
    {
        NSExpression *self_ = [NSExpression expressionForEvaluatedObject];
        NSExpression *parsed;

        NSLog(@"+expressionForEvaluatedObject: type %lu (want %lu)",
              (unsigned long)[self_ expressionType],
              (unsigned long)NSEvaluatedObjectExpressionType);

        if ([self_ expressionType] != NSEvaluatedObjectExpressionType)
        {
            failures++;
        }

        /* The same expression as the parser produces it. */
        parsed = [[NSPredicate predicateWithFormat: @"SELF == %@", @"x"]
                     performSelector: @selector(leftExpression)];

        NSLog(@"SELF parsed from a format: type %lu (want %lu)",
              (unsigned long)[parsed expressionType],
              (unsigned long)NSEvaluatedObjectExpressionType);

        if ([parsed expressionType] != NSEvaluatedObjectExpressionType)
        {
            failures++;
        }

        /* And it still evaluates to the object it is given, and still
           reads back from an archive as itself. */
        if (![[self_ expressionValueWithObject: @"hello" context: nil]
                isEqual: @"hello"])
        {
            NSLog(@"FAIL: SELF did not answer with the object");
            failures++;
        }

        NSExpression *back = [NSKeyedUnarchiver unarchiveObjectWithData:
            [NSKeyedArchiver archivedDataWithRootObject: self_]];

        if ([back expressionType] != NSEvaluatedObjectExpressionType)
        {
            NSLog(@"FAIL: SELF came back from an archive as type %lu",
                  (unsigned long)[back expressionType]);
            failures++;
        }
    }

    NSLog(@"%s", failures == 0 ? "PASS" : "FAIL");

    return (failures == 0) ? 0 : 1;
}
