/* Repro for the predicate equality-option gap
   (see gnustep-base-predicate-equality-options.patch).

   The [c] and [d] options are honoured by every comparison except the
   one people write most: equality.  "Ada" ==[c] "ada" is true on macOS
   and false in gnustep-base, because -[GSComparisonPredicate
   evaluateWithObject:] answers == and != with -isEqual:, which can
   express neither option, while the compare options it has just worked
   out are used only by the ordering and matching operators.

   The option is parsed and stored - the predicate prints as
   "name ==[c] ada" - so the mismatch is silent: a filter that looks
   case-insensitive simply misses rows.

   With the patch, two strings compared with either option are compared
   as strings, and everything else still goes through -isEqual:.

   Build and run (against an installed gnustep-base):

       . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
       clang repro-nspredicate-equality-options.m -o repro \
           $(gnustep-config --objc-flags) $(gnustep-config --base-libs)
       ./repro

   Exit status 0 with the patch applied, 1 without it. */
#import <Foundation/Foundation.h>

static int failures = 0;

static void
check(const char *what, BOOL got, BOOL want)
{
    if (got != want)
    {
        failures++;
        NSLog(@"FAIL %s: got %d, want %d", what, (int)got, (int)want);
    }
    else
    {
        NSLog(@"ok   %s (%d)", what, (int)got);
    }
}

int
main(void)
{
    @autoreleasepool
    {
        NSDictionary *ada = [NSDictionary dictionaryWithObject: @"Ada"
                                                        forKey: @"name"];

        /* The gap itself. */
        check("name ==[c] \"ada\"",
              [[NSPredicate predicateWithFormat: @"name ==[c] %@", @"ada"]
                  evaluateWithObject: ada],
              YES);
        check("name !=[c] \"ada\"",
              [[NSPredicate predicateWithFormat: @"name !=[c] %@", @"ada"]
                  evaluateWithObject: ada],
              NO);

        /* Case still matters when no option is given. */
        check("name == \"ada\"",
              [[NSPredicate predicateWithFormat: @"name == %@", @"ada"]
                  evaluateWithObject: ada],
              NO);
        check("name == \"Ada\"",
              [[NSPredicate predicateWithFormat: @"name == %@", @"Ada"]
                  evaluateWithObject: ada],
              YES);

        /* An option on two things that are not strings changes nothing:
           they are still compared with -isEqual:. */
        NSDictionary *counted = [NSDictionary dictionaryWithObject:
            [NSNumber numberWithInt: 41] forKey: @"age"];

        check("age ==[c] 41",
              [[NSPredicate predicateWithFormat: @"age ==[c] %d", 41]
                  evaluateWithObject: counted],
              YES);
        check("age ==[c] 42",
              [[NSPredicate predicateWithFormat: @"age ==[c] %d", 42]
                  evaluateWithObject: counted],
              NO);

        /* Ordering and matching, which already honoured the options,
           still do. */
        check("name <[c] \"b\"",
              [[NSPredicate predicateWithFormat: @"name <[c] %@", @"b"]
                  evaluateWithObject: ada],
              YES);
        check("name BEGINSWITH[c] \"a\"",
              [[NSPredicate predicateWithFormat: @"name BEGINSWITH[c] %@", @"a"]
                  evaluateWithObject: ada],
              YES);
    }

    NSLog(@"%s", failures == 0 ? "PASS" : "FAIL");

    return (failures == 0) ? 0 : 1;
}
