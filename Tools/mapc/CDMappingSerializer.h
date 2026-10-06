/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/Foundation.h>

@class NSMappingModel;

/* Writes a mapping model back into the form Xcode's editor reads and
   saves - an .xcmappingmodel holding an xcmapping.xml - so that a mapping
   made here opens there, and one made there opens here.

   What the file keeps is what an author chose; the rest is left for the
   compiler to work out again, so an expression that is simply "the source
   object's property of this name" is written as no expression at all. */
@interface CDMappingSerializer : NSObject

/* Writing over a file keeps what only Xcode can put in it - see the
   implementation - so a mapping model made there survives a save here. */
+ (NSString *)xcmappingXMLForMappingModel:(NSMappingModel *)model
                          sourceModelPath:(NSString *)sourceModelPath
                     destinationModelPath:(NSString *)destinationModelPath
                                    error:(NSError **)error;

/* Whether an expression is the one the compiler works out for a property
   of this name, rather than one an author wrote.  The serializer leaves
   those out of a file; an editor shows them as nothing. */
+ (BOOL)isGeneratedExpression:(NSExpression *)expression forPropertyNamed:(NSString *)name;

/* Takes apart the expression that fills a relationship through another
   entity mapping - see +[CDMappingCompiler
   valueExpressionForRelationshipKeyPath:throughMapping:] - into the two
   things Xcode's inspector shows for it.  NO for any other expression. */
+ (BOOL)relationshipExpression:(NSExpression *)expression
                   mappingName:(NSString **)mappingName
                       keyPath:(NSString **)keyPath;

/* The path a mapping model at one place records for a model at another,
   as Xcode records it: relative to the project the two are in - the
   nearest directory above the mapping model holding an .xcodeproj that
   holds the model too - or, outside a project, to the nearest directory
   holding both.  The compiler looks for a model by that path against each
   directory above the mapping model, so either is found again. */
+ (NSString *)recordedPathOfModelAtPath:(NSString *)modelPath
                  forMappingModelAtPath:(NSString *)mappingPath;

+ (BOOL)writeMappingModel:(NSMappingModel *)model
                   toPath:(NSString *)path
          sourceModelPath:(NSString *)sourceModelPath
     destinationModelPath:(NSString *)destinationModelPath
                    error:(NSError **)error;

@end
