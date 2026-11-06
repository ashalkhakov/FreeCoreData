/* UDCode's Core Data extension — the edits that turn a document's text
   into the text an editor wrote: one for each run of lines that differs
   (UDPieceTable's line diff, VS Code's), made together, so they are one
   step of the text's undo and a diff of the file shows the lines a change
   touched.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <Foundation/Foundation.h>
#import <UDPieceTable/UDTextModel.h>

/* The edits that make `model`'s text `text`; none when it is that already. */
NSArray<UDTextModelEdit *> *MBUEditsToText(UDTextModel *model, NSString *text);

/* `model`'s text made `text`, as one edit of it; NO when it was that already. */
BOOL MBUWriteText(UDTextModel *model, NSString *text);
