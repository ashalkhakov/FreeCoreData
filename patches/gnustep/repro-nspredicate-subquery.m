/* Repro for the missing SUBQUERY support
   (see gnustep-base-predicate-subquery.patch).

   gnustep-base names NSSubqueryExpressionType in its enumeration and
   declares an empty GSSubqueryExpression, but there is nothing behind
   either: no +expressionForSubquery:usingIteratorVariable:predicate:,
   no evaluation, and nothing in the parser.  A format string containing
   SUBQUERY(...) is read as a call to a function called SUBQUERY and
   raises while parsing.

   The raise comes from an unrelated place - "[GSVariableExpression
   -keyPath] should be overridden by subclass" - because the parser asks
   an expression for its key path to work out what it is looking at, and
   -keyPath raises for the kinds that have none.  $x.y therefore cannot
   be parsed either, whether or not a subquery is involved.

   With the patch the parser asks about the kind before asking for the
   key path, and SUBQUERY(collection, $x, predicate) builds an
   expression that answers with the members of the collection its
   predicate accepts.

   Build and run (against an installed gnustep-base):

       . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
       clang repro-nspredicate-subquery.m -o repro \
           $(gnustep-config --objc-flags) $(gnustep-config --base-libs)
       ./repro

   Exit status 0 with the patch applied, 1 without it. */
#import <Foundation/Foundation.h>

static int failures = 0;

@interface ReproPerson : NSObject
{
    NSString *_name;
    int       _age;
    NSArray  *_friends;
}
@end

@implementation ReproPerson

+ (ReproPerson *) named: (NSString *)name age: (int)age
{
    ReproPerson *person = [[[ReproPerson alloc] init] autorelease];

    person->_name = [name copy];
    person->_age = age;
    person->_friends = [[NSArray alloc] init];

    return person;
}

- (NSString *) name              { return _name; }
- (int) age                      { return _age; }
- (NSArray *) friends            { return _friends; }
- (void) setFriends: (NSArray *)friends { ASSIGN(_friends, friends); }

@end

static void
check(const char *what, BOOL condition)
{
    if (condition)
    {
        NSLog(@"ok   %s", what);
    }
    else
    {
        NSLog(@"FAIL %s", what);
        failures++;
    }
}

int
main(void)
{
    @autoreleasepool
    {
        ReproPerson *ada = [ReproPerson named: @"Ada" age: 36];
        ReproPerson *alan = [ReproPerson named: @"Alan" age: 41];
        ReproPerson *grace = [ReproPerson named: @"Grace" age: 45];

        [ada setFriends: [NSArray arrayWithObjects: alan, grace, nil]];
        [alan setFriends: [NSArray arrayWithObject: ada]];

        /* A key path on the iterator variable, which is what the parser
           could not read at all. */
        @try
        {
            NSPredicate *dotted;

            dotted = [NSPredicate predicateWithFormat: @"$x.age > %d", 40];
            check("$x.age parses", dotted != nil);
        }
        @catch (NSException *exception)
        {
            NSLog(@"FAIL $x.age parses: %@ -- %@",
                  [exception name], [exception reason]);
            failures++;
        }

        /* The subquery itself, built by hand ... */
        NSExpression *subquery;

        subquery = [NSExpression expressionForSubquery:
                        [NSExpression expressionForKeyPath: @"friends"]
                                 usingIteratorVariable: @"f"
                                             predicate:
                        [NSPredicate predicateWithFormat: @"$f.age > %d", 40]];

        check("type is NSSubqueryExpressionType",
              [subquery expressionType] == NSSubqueryExpressionType);
        check("variable answers",
              [[subquery variable] isEqualToString: @"f"]);
        check("collection answers",
              [[[subquery collection] keyPath] isEqualToString: @"friends"]);
        check("predicate answers", [subquery predicate] != nil);

        NSArray *older = [subquery expressionValueWithObject: ada context: nil];

        check("Ada has two friends over forty", [older count] == 2);
        check("Alan has none",
              [[subquery expressionValueWithObject: alan context: nil]
                  count] == 0);

        /* ... and as a format string parses it. */
        @try
        {
            NSPredicate *sociable;

            sociable = [NSPredicate predicateWithFormat:
                @"SUBQUERY(friends, $f, $f.age > %d).@count > %d", 40, 1];

            check("SUBQUERY(...).@count parses", sociable != nil);
            check("Ada matches", [sociable evaluateWithObject: ada]);
            check("Alan does not", ![sociable evaluateWithObject: alan]);
            check("Grace does not", ![sociable evaluateWithObject: grace]);

            /* It also prints back the way it was written. */
            check("prints as SUBQUERY(...)",
                  [[sociable predicateFormat] hasPrefix: @"SUBQUERY(friends, $f,"]);
        }
        @catch (NSException *exception)
        {
            NSLog(@"FAIL SUBQUERY parses: %@ -- %@",
                  [exception name], [exception reason]);
            failures++;
        }
    }

    NSLog(@"%s", failures == 0 ? "PASS" : "FAIL");

    return (failures == 0) ? 0 : 1;
}
