/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

/* momc - compiles Xcode data model sources (.xcdatamodeld /
   .xcdatamodel) into the runtime form FreeCoreData loads
   (.momd / .mom), and decompiles those artifacts back into source.
   The compiler lives in CDModelCompiler, its inverse in
   CDModelSerializer; this file is only the command line. */

#import <Foundation/Foundation.h>
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"
#import "CDCodeGenerator.h"

static void usage(void){
   fprintf(stderr,"usage: momc <Model.xcdatamodeld> <Model.momd>\n"
                  "       momc <Model.xcdatamodel> <Model.mom>\n"
                  "       momc --decompile <Model.momd> <Model.xcdatamodeld>\n"
                  "       momc --decompile <Model.mom> <Model.xcdatamodel>\n"
                  "       momc --codegen [--all] <Model.xcdatamodeld|.xcdatamodel> <output-dir>\n"
                  "         generates Xcode-style NSManagedObject subclass sources for\n"
                  "         entities whose Codegen is Class Definition or Category/Extension\n"
                  "         (--all: every entity with a custom class)\n");
}

/* The current .xcdatamodel version inside a .xcdatamodeld, per
   .xccurrentversion (first version alphabetically when unmarked,
   matching compileModelSourceAtPath). */
static NSString *currentVersionPath(NSString *source){
   if([[source pathExtension] isEqualToString:@"xcdatamodel"])
    return source;

   NSMutableArray *versions=[NSMutableArray array];
   for(NSString *name in [[[NSFileManager defaultManager]
           contentsOfDirectoryAtPath:source error:NULL]
           sortedArrayUsingSelector:@selector(compare:)])
    if([[name pathExtension] isEqualToString:@"xcdatamodel"])
     [versions addObject:name];
   if([versions count]==0)
    return nil;

   NSString *current=[versions objectAtIndex:0];
   NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:
       [source stringByAppendingPathComponent:@".xccurrentversion"]];
   NSString *marked=[info objectForKey:@"_XCCurrentVersionName"];
   if(marked!=nil && [versions containsObject:marked])
    current=marked;
   return [source stringByAppendingPathComponent:current];
}

static int runCodegen(NSString *source,NSString *outputDir,BOOL all){
   NSString *modelPath=currentVersionPath(source);
   if(modelPath==nil){
    fprintf(stderr,"momc: error: %s contains no .xcdatamodel versions\n",
        [source UTF8String]);
    return 1;
   }

   NSError *error=nil;
   NSManagedObjectModel *model=[CDModelCompiler compileModelAtPath:modelPath
                                                             error:&error];
   if(model==nil){
    fprintf(stderr,"momc: error: %s\n",[[error localizedDescription] UTF8String]);
    return 1;
   }

   NSArray *entities=[CDCodeGenerator generatableEntitiesInModel:model
                                                      onlyMarked:!all];
   if([entities count]==0){
    fprintf(stderr,"momc: warning: no entities to generate for%s\n",
        all?" (none has a custom class)"
           :" (none is marked Class Definition or Category/Extension; --all overrides)");
    return 0;
   }

   NSArray *written=[CDCodeGenerator writeSourcesForEntities:entities
                                                 toDirectory:outputDir
                                                       error:&error];
   if(written==nil){
    fprintf(stderr,"momc: error: %s\n",[[error localizedDescription] UTF8String]);
    return 1;
   }
   for(NSString *filename in written)
    printf("%s\n",[[outputDir stringByAppendingPathComponent:filename] UTF8String]);
   return 0;
}

int main(int argc,const char *argv[]){
   @autoreleasepool {
    NSArray *arguments=[[NSProcessInfo processInfo] arguments];
    BOOL decompile=NO;

    if([arguments count]>=2 && [[arguments objectAtIndex:1] isEqualToString:@"--codegen"]){
     NSMutableArray *rest=[[arguments subarrayWithRange:
         NSMakeRange(2,[arguments count]-2)] mutableCopy];
     BOOL all=[rest containsObject:@"--all"];
     [rest removeObject:@"--all"];
     if([rest count]!=2){
      usage();
      return 1;
     }
     [CDModelCompiler setWarningHandler:^(NSString *message){
      fprintf(stderr,"momc: warning: %s\n",[message UTF8String]);
     }];
     return runCodegen([rest objectAtIndex:0],[rest objectAtIndex:1],all);
    }

    if([arguments count]==4 && [[arguments objectAtIndex:1] isEqualToString:@"--decompile"]){
     decompile=YES;
     arguments=[NSArray arrayWithObjects:[arguments objectAtIndex:0],
                [arguments objectAtIndex:2],[arguments objectAtIndex:3],nil];
    }

    if([arguments count]!=3){
     usage();
     return 1;
    }

    [CDModelCompiler setWarningHandler:^(NSString *message){
     fprintf(stderr,"momc: warning: %s\n",[message UTF8String]);
    }];

    NSError *error=nil;
    BOOL ok;

    if(decompile)
     ok=[CDModelSerializer decompileModelArtifactAtPath:[arguments objectAtIndex:1]
                                                 toPath:[arguments objectAtIndex:2]
                                                  error:&error];
    else
     ok=[CDModelCompiler compileModelSourceAtPath:[arguments objectAtIndex:1]
                                           toPath:[arguments objectAtIndex:2]
                                            error:&error];
    if(!ok){
     fprintf(stderr,"momc: error: %s\n",[[error localizedDescription] UTF8String]);
     return 1;
    }
   }
   return 0;
}
