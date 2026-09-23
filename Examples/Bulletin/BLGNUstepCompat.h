/*
 * This file is part of Bulletin, the FreeCoreData persistent-history
 * example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
/*
 * Force-included on GNUstep (see GNUmakefile.preamble); never seen by
 * Xcode.  AppKit names that a given gnustep-gui does not have yet get
 * defined here in terms of the ones it has, so the sources can be written
 * against current AppKit and stay free of #ifdefs.
 *
 * Keep it small: anything that needs behaviour, not just a name, belongs
 * upstream in gnustep-gui.
 */
#ifndef BLGNUstepCompat_h
#define BLGNUstepCompat_h

#ifdef __OBJC__
#import <AppKit/AppKit.h>
#endif

#endif
