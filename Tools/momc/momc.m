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

static void usage(void){
   fprintf(stderr,"usage: momc <Model.xcdatamodeld> <Model.momd>\n"
                  "       momc <Model.xcdatamodel> <Model.mom>\n"
                  "       momc --decompile <Model.momd> <Model.xcdatamodeld>\n"
                  "       momc --decompile <Model.mom> <Model.xcdatamodel>\n");
}

int main(int argc,const char *argv[]){
   @autoreleasepool {
    NSArray *arguments=[[NSProcessInfo processInfo] arguments];
    BOOL decompile=NO;

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
