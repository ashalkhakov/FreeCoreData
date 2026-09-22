/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/Foundation.h>

@class NSManagedObjectModel;

extern NSString * const CDModelSerializerErrorDomain;

/* The inverse of CDModelCompiler: turns an NSManagedObjectModel back
   into the Xcode .xcdatamodel "contents" XML, in the same spelling
   Xcode writes ("Integer 32", "Nullify", derivationExpression
   "uppercase:(title)", ...).  compile(serialize(model)) is verified to
   reproduce the model - the ModelBuilder editor uses this pair as its
   document format, and momc uses it to decompile .momd back to source.

   entityLayouts (optional) carries the editor's canvas geometry for the
   <elements> section: entity name -> dictionary with "positionX",
   "positionY", "width", "height" string values.  Without it, default
   geometry is written. */
@interface CDModelSerializer : NSObject

+ (NSString *)contentsXMLForModel:(NSManagedObjectModel *)model
                    entityLayouts:(NSDictionary *)entityLayouts
                            error:(NSError **)error;

+ (NSString *)contentsXMLForModel:(NSManagedObjectModel *)model
                            error:(NSError **)error;

/* momc's reverse gear: turns a compiled artifact back into editable
   source.
     Model.momd -> Model.xcdatamodeld  (every version, .xccurrentversion)
     Model.mom  -> Model.xcdatamodel   (single version directory)
   Canvas geometry is not stored in compiled models, so the <elements>
   section is written with default positions. */
+ (BOOL)decompileModelArtifactAtPath:(NSString *)artifactPath
                              toPath:(NSString *)destinationPath
                               error:(NSError **)error;

@end
