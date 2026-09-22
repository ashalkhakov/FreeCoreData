/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Foundation/Foundation.h>

@class NSManagedObjectModel;
@class NSEntityDescription;

/* Generates Xcode-style Objective-C NSManagedObject subclass sources
   from a compiled model, honoring the codegen metadata the momc layer
   round-trips (codeGenerationType, usesScalarValueType).

   Per entity, the codeGenerationType decides the file set:
     "class"    ClassName+CoreDataClass.h/.m (the subclass, generated
                but yours to extend) and
                ClassName+CoreDataProperties.h/.m (the @dynamic
                property category, regenerated every time)
     "category" only the +CoreDataProperties pair; the header imports
                "ClassName.h", the class definition being yours
     nil        skipped by the marked-only paths; an explicit
                sourcesForEntity: treats it as "class" (Xcode's
                Editor > Create NSManagedObject Subclass... does the
                same for Manual/None entities)

   Entities whose representedClassName is NSManagedObject (or empty)
   have nothing to generate and are never eligible. */
@interface CDCodeGenerator : NSObject

/* Entities worth generating for, sorted by name.  onlyMarked limits
   the set to entities carrying a codeGenerationType. */
+ (NSArray *)generatableEntitiesInModel:(NSManagedObjectModel *)model
                             onlyMarked:(BOOL)onlyMarked;

/* filename -> file contents for one entity (2 or 4 entries, per the
   table above). */
+ (NSDictionary *)sourcesForEntity:(NSEntityDescription *)entity;

/* Writes every entity's sources into directory (created if missing).
   Returns the filenames written, nil on the first failure. */
+ (NSArray *)writeSourcesForEntities:(NSArray *)entities
                         toDirectory:(NSString *)directory
                               error:(NSError **)error;

@end
