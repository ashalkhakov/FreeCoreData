/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#import <Foundation/NSKeyedArchiver.h>

/* What -[NSManagedObjectModel copy] archives the model with.  A copy keeps
   exactly the indexes the model has, as Apple's does, so an attribute does
   not archive its indexed flag to it: reading that back makes an index of
   each indexed attribute, beside the one that marked it. */
@interface CDModelCopyArchiver : NSKeyedArchiver
@end
