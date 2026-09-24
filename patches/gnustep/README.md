# GNUstep patches carried by this project

Ten fixes, written for upstream and applied by
`.github/scripts/dependencies.sh` when CI and the release build the GNUstep
stack. They are held here while upstream is in code freeze; send them once
it lifts, and delete each one (and its `patch` line in the script) when it
has been merged.

## gnustep-gui-tableview-column-autoresizing-style.patch (libs-gui)

`-[NSTableView setColumnAutoresizingStyle:]` and `-columnAutoresizingStyle`
were `// FIXME` stubs: the xib loader decoded the style, the table dropped
it. A table in a nib therefore never followed its scroll view's width —
ModelBuilder's tables kept their nib width in a wider window (a grey strip
beside each) or overflowed a narrower one. The table's own
`-superviewFrameChanged:` heuristic only tracks a table that was exactly as
wide as its clip view at the previous change, which stops holding after the
first layout pass.

The patch gives the style an ivar, decodes and encodes it
(`NSColumnAutoresizingStyle`), and on a superview frame change sizes the
columns to the visible width the way the style says — first column only,
last column only, uniformly, sequentially from the last, or from the
first — within each autoresizing column's minimum and maximum. Tables built
in code default to no style, so they keep the resizing they have today.

## gnustep-gui-xib-date-picker.patch (libs-gui)

The recent date picker work made NSDatePicker usable, but the xib loader
(`GSXib5KeyedUnarchiver`) still knew nothing about it: a xib describes a
date picker with attributes on its cell (`datePickerStyle`,
`datePickerMode`, `useCurrentDate`), a `<datePickerElements>` element and
`<date>` elements carrying `timeIntervalSinceReferenceDate`, and none of
those reach the archive keys `NSDatePickerCell` reads. Every date picker
from a xib came up with no fields (elements `0`) and a date two seconds
into 2001. The patch adds decoders for `NSDatePickerElements`,
`NSDatePickerType`, `NSDatePickerMode`, `NSDateValue` (the current date
when the xib says `useCurrentDate`), `NSMinDate` and `NSMaxDate`.

## eau-theme-keep-nib-textfield-bezel.patch (gershwin-eau-theme)

Eau swizzles `-[NSTextField initWithFrame:]` and `-initWithCoder:` to make
unbezeled the default ("labels are the common case"). For a field made in
code that is a default; for one loaded from a nib it overrides what the nib
says, so every input field in a nib drew flat, and — without the bezel's
inset — with its text about 2 pt above its label. The patch leaves
nib-loaded fields as the nib has them and keeps the default for fields made
in code.

## gnustep-gui-arraycontroller-selection-kvo.patch (libs-gui)

`-[NSArrayController setSelectionIndexes:]` changed the selection without
a word to key-value observers: automatic KVO fired for
`selectionIndexes` itself (it is the setter), but nothing was declared
to depend on it, so `selection`, `selectedObjects`, `canRemove` and
`canSelectNext/Previous` stayed silent. Every binding that follows the
selection therefore froze at its initial state - a Remove button bound
to `canRemove` stayed grey forever, a date picker bound through
`selection.date` kept the first row's date. `-selection` itself also
answered with the raw content array, so `selection.<key>` collected
over every row and could not be observed at all (observing a key on an
array raises).

The patch declares the dependent keys with
`+keyPathsForValuesAffecting...` and overrides `-selection` to return
the selected object when exactly one row is selected, nil otherwise
(full Cocoa fidelity wants a multi-selection proxy answering
`NSMultipleValuesMarker`; noted in the code for the day a binding here
needs it).

`repro-nsarraycontroller-selection-kvo.m` beside this file demonstrates
the gap and proves the fix: it registers observers for the seven
selection-dependent key paths, changes the selection, and reports which
of them heard about it - exit 0 patched, 1 unpatched. Build and run
instructions are in its header; send it upstream together with the
patch.

## gnustep-base-dateformatter-cell-behavior.patch (libs-base)

`-[NSDateFormatter stringForObjectValue:]` - the NSFormatter entry
point every NSCell calls, so the way a date reaches the screen from a
text field or a bound table column - always formatted with the 10.0
calendar-format code, even when the formatter was explicitly set to
`NSDateFormatterBehavior10_4`; the modern ICU machinery lives only in
`-stringFromDate:`. An ICU pattern such as `yyyy-MM-dd` has no
%-escapes, so every date column in Staffbook showed the literal
pattern instead of the date. `-getObjectValue:forString:...`
mis-parsed for the same reason.

The patch makes both entry points delegate to the modern
`-stringFromDate:` / `-dateFromString:` when the instance's behavior
is `NSDateFormatterBehavior10_4`, and leaves the 10.0 path untouched
for everyone who has not asked for the modern behavior.

`repro-nsdateformatter-cell-behavior.m` beside this file demonstrates
the gap and proves the fix (exit 0 patched, 1 unpatched); send it
upstream together with the patch.

## gnustep-base-keyedarchiver-secure-coding.patch (libs-base)

`+[NSKeyedArchiver archivedDataWithRootObject:requiringSecureCoding:error:]`
— the modern (10.13) archiving entry point, and the only non-deprecated
one on macOS — answered nil whenever secure coding was requested,
without setting the error, even for objects that fully adopt
NSSecureCoding: the class method simply skipped the whole encode when
`requiresSecureCoding` was YES, although the archiver instance has
carried a `requiresSecureCoding` flag for years. CoreData's
NSPersistentHistoryToken (which applications archive to remember their
position in a store's history) could not be persisted through the
documented API.

The patch makes the method encode with the archiver's flag set, checks
that the root object's class supports secure coding (reporting a
violation through the error as `NSCoderInvalidValueError` instead of
silently answering nil for everything), and clears the error on
success.

`repro-nskeyedarchiver-secure-coding.m` beside this file demonstrates
the gap and proves the fix (exit 0 patched, 1 unpatched); send it
upstream together with the patch.

## gnustep-base-predicate-equality-options.patch (libs-base)

The `[c]` and `[d]` options are honoured by every comparison except the
one people write most. `-[GSComparisonPredicate evaluateWithObject:]`
works out the string compare options from the predicate's options and
then uses them only for ordering and matching: `==` and `!=` are answered
with `-isEqual:`, which can express neither option. `"Ada" ==[c] "ada"` is
true on macOS and false here.

The option is parsed and kept - the predicate even prints as
`name ==[c] ada` - so the mismatch is silent: a filter that reads as
case-insensitive simply misses rows. The patch compares two strings with
the options when either is set, and leaves everything else going through
`-isEqual:`.

`repro-nspredicate-equality-options.m` beside this file demonstrates the
gap and proves the fix (exit 0 patched, 1 unpatched); send it upstream
together with the patch.

## gnustep-base-expression-self-type.patch (libs-base)

Every kind of `NSExpression` is built through `-initWithExpressionType:`,
which is what `-expressionType` answers with - every kind but one. The
shared expression behind `+expressionForEvaluatedObject` is built with
`+new`, so its type stays zero, and zero is
`NSConstantValueExpressionType`: `SELF` reports itself as a constant
value.

Anything that switches on `-expressionType` is then wrong about `SELF` -
a persistent store translating a predicate either mistakes it for a
constant and asks for a `constantValue` it has not got, or quietly
declines to translate something it understands perfectly well. The patch
builds the shared expression with its own type, like all the others.

`repro-nsexpression-self-type.m` beside this file demonstrates the gap and
proves the fix (exit 0 patched, 1 unpatched); send it upstream together
with the patch.

## gnustep-base-expression-binary-coding.patch (libs-base)

Four kinds of expression share the class that holds a left and a right
expression: a key path composition (`$x.y`, and anything else written with
a dot after something that is not a plain key path), a union, an
intersection and a difference. None of them implements
`-encodeWithCoder:`, so they inherit `NSExpression`'s, which raises
`should be overridden by subclass`.

Archiving a predicate is how a Core Data model stores a fetch request
template and how one process hands a predicate to another, so a predicate
with `$x.y` in it could not be saved at all. The patch encodes the two
halves and writes out which of the four kinds it is, so that one
initialiser reads them all back.

`repro-nsexpression-binary-coding.m` beside this file demonstrates the gap
and proves the fix (exit 0 patched, 1 unpatched); send it upstream
together with the patch.

## gnustep-base-predicate-subquery.patch (libs-base)

`NSSubqueryExpressionType` is named in the enumeration and
`GSSubqueryExpression` is declared with an empty implementation, but there
is nothing behind either: no
`+expressionForSubquery:usingIteratorVariable:predicate:`, no evaluation,
and nothing in the parser. `SUBQUERY(...)` in a format string is read as a
call to a function named `SUBQUERY` and raises while parsing.

The raise comes from somewhere unexpected - `[GSVariableExpression
-keyPath] should be overridden by subclass` - and that is a second gap
behind the first: the parser asks an expression for its key path to decide
what it is looking at, and `-keyPath` raises for the kinds that have none.
`$x.y` could not be parsed either, subquery or no subquery.

The patch adds the factory method, the expression class (evaluation,
description, coding, equality and substitution) and the parser clause, and
makes the parser ask about the kind before it asks for the key path. The
iterator variable is bound by substituting it into the subpredicate for
each member, since `-evaluateWithObject:` passes no context for a variable
to be looked up in.

`repro-nspredicate-subquery.m` beside this file demonstrates the gap and
proves the fix (exit 0 patched, 1 unpatched); send it upstream together
with the patch.

These four are what this project's SQL backends found: a store translates
a predicate by walking it, so a predicate the framework cannot parse, or
an expression that will not say what kind it is, stops the translation
before it starts. With them applied, `SUBQUERY(employees, $e, $e.age >
40).@count > 1` reaches the database as a correlated `COUNT`, the same
statement Apple's CoreData produces.
