# CDLauncher

The chooser the Linux AppImage opens: one button each for Model Builder,
Staffbook and Employee Directory, launched as sibling application
bundles (the pattern of XFormsKit's XFormsLauncher, by way of
UDQuakeTools' UDLauncher).  GNUstep-only - a Mac ships the apps
separately and has nothing to choose between - and built entirely in
code, with no XIB to load.

The AppImage's `AppRun` starts it when the image is run bare; a first
argument of `modelbuilder`, `staffbook` or `employeedirectory` (or a
model document path, which Model Builder opens) starts that app
directly instead.
