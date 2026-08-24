/* This file is part of the CoreData framework port for GNUstep.
   Ported from the Cocotron project (https://github.com/cjwl/cocotron).

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net>
   Copyright (c) 2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSSet.h>

@class NSManagedObjectContext, NSManagedObject;

/* The set handed out by -valueForKey: for an unordered to-many
   relationship.  A LIVE, MUTABLE view: reads reflect the current
   membership, and addObject:/removeObject: route through the owning
   object's setter so change tracking and inverse maintenance apply.

   DELIBERATE DIVERGENCE (Mac-verified): Apple's faulting set also
   accepts in-place mutation, but silently bypasses change processing -
   no inverse maintenance, owner not marked updated (the footgun its
   docs warn about; mutableSetValueForKey: is the tracked channel).
   The port routes instead because GNUstep's NSArrayController mutates
   a bound contentSet in place: untracked semantics there would mean
   UI edits that never save. */
@interface NSManagedObjectSet : NSMutableSet {
    NSManagedObjectContext *_context;
    NSManagedObject *_owner;
    NSString *_key;
    NSSet *_set;
}

/* Live relationship view (the normal case). */
- initWithManagedObject:(NSManagedObject *)owner key:(NSString *)key;

/* Immutable snapshot over a set of object IDs (mutations raise). */
- initWithManagedObjectContext:(NSManagedObjectContext *)context set:(NSSet *)set;

@end
