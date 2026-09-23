# CDLauncher

The chooser the Linux AppImage opens: one button each for Model Builder,
Staffbook, Employee Directory and Bulletin, launched as sibling
application bundles (the pattern of XFormsKit's XFormsLauncher, by way
of UDQuakeTools' UDLauncher).  GNUstep-only - a Mac ships the apps
separately and has nothing to choose between - and built entirely in
code, with no XIB to load.

The AppImage's `AppRun` starts it when the image is run bare; a first
argument of `modelbuilder`, `staffbook`, `employeedirectory` or
`bulletin` (or a model document path, which Model Builder opens) starts
that app directly instead.
