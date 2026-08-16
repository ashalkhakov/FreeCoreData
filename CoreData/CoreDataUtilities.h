/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* CoreDataUtilities.h - GNUstep compatibility shims for Cocotron CoreData port
   This header provides replacements for Cocotron-specific macros from
   Foundation/NSRaise.h that are not available in GNUstep-base. */

#ifndef COREDATA_UTILITIES_H
#define COREDATA_UTILITIES_H

#import <Foundation/Foundation.h>

/* NSUnimplementedMethod() - raises NSInvalidArgumentException noting the
   unimplemented method and the receiver class. */
#ifndef NSUnimplementedMethod
#define NSUnimplementedMethod() \
    do { \
        [NSException raise:NSInvalidArgumentException \
                    format:@"%@[%@ %@] not implemented", \
                           [self isKindOfClass:[self class]] ? @"-" : @"+", \
                           NSStringFromClass([self class]), \
                           NSStringFromSelector(_cmd)]; \
    } while(0)
#endif

/* NSInvalidAbstractInvocation() - raises NSInvalidArgumentException noting
   that an abstract method was directly called. */
#ifndef NSInvalidAbstractInvocation
#define NSInvalidAbstractInvocation() \
    do { \
        [NSException raise:NSInvalidArgumentException \
                    format:@"%@[%@ %@] is an abstract method", \
                           [self isKindOfClass:[self class]] ? @"-" : @"+", \
                           NSStringFromClass([self class]), \
                           NSStringFromSelector(_cmd)]; \
    } while(0)
#endif

#endif /* COREDATA_UTILITIES_H */
