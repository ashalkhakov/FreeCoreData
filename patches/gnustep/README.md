# GNUstep patches carried by this project

Four fixes, written for upstream and applied by
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
