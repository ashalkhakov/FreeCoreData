# GNUstep patches carried by this project

Two fixes, written for upstream and applied by
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

## eau-theme-keep-nib-textfield-bezel.patch (gershwin-eau-theme)

Eau swizzles `-[NSTextField initWithFrame:]` and `-initWithCoder:` to make
unbezeled the default ("labels are the common case"). For a field made in
code that is a default; for one loaded from a nib it overrides what the nib
says, so every input field in a nib drew flat, and — without the bezel's
inset — with its text about 2 pt above its label. The patch leaves
nib-loaded fields as the nib has them and keeps the default for fields made
in code.
