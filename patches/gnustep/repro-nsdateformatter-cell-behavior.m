/* Repro for the NSDateFormatter cell-formatting gap
   (see gnustep-base-dateformatter-cell-behavior.patch).

   -stringForObjectValue: is the NSFormatter entry point every NSCell
   calls, so it is how a date reaches the screen from a text field or a
   table column.  gnustep-base keeps the modern (10.4, ICU) machinery
   in -stringFromDate: only; -stringForObjectValue: always formats with
   the 10.0 calendar-format code, even when the formatter is explicitly
   set to NSDateFormatterBehavior10_4.  An ICU pattern such as
   yyyy-MM-dd has no %-escapes, so a bound table column showed the
   pattern itself instead of the date.  -getObjectValue:forString:...
   mis-parses for the same reason.

   Build and run (against an installed gnustep-base):

       . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
       clang repro-nsdateformatter-cell-behavior.m -o repro \
           $(gnustep-config --objc-flags) $(gnustep-config --base-libs)
       ./repro

   Exit status 0 with the patch applied, 1 without it. */
#import <Foundation/Foundation.h>

int main(void)
{
    @autoreleasepool {
        int failures = 0;

        NSDateFormatter *day = [[NSDateFormatter alloc] init];
        [day setFormatterBehavior:NSDateFormatterBehavior10_4];
        [day setDateFormat:@"yyyy-MM-dd"];
        [day setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

        NSDate *date = [NSDate dateWithTimeIntervalSince1970:1756500000];
        NSString *direct = [day stringFromDate:date];      /* the 10.4 API */
        NSString *cell = [day stringForObjectValue:date];  /* what cells call */

        printf("stringFromDate:        %s\n", [direct UTF8String]);
        printf("stringForObjectValue:  %s\n", [cell UTF8String]);
        if (![cell isEqual:direct]) {
            printf("MISMATCH: cells format differently from the 10.4 API\n");
            failures++;
        }

        id parsed = nil;
        NSString *why = nil;
        BOOL ok = [day getObjectValue:&parsed forString:direct
                     errorDescription:&why];
        printf("getObjectValue:        %s (%s)\n",
               ok ? "parsed" : "FAILED",
               parsed ? [[parsed description] UTF8String]
                      : [(why ?: @"no error text") UTF8String]);
        /* Round trip: parsing what the formatter itself printed must
           give the same day back. */
        if (!ok || parsed == nil
            || ![[day stringFromDate:parsed] isEqual:direct]) {
            printf("MISMATCH: round trip through the cell parse path\n");
            failures++;
        }

        printf(failures ? "FAIL: %d check(s)\n" : "PASS\n", failures);
        return failures ? 1 : 0;
    }
}
