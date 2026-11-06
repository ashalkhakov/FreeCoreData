/* UDCode's Core Data extension — the text edits (see MBUTextEdits.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBUTextEdits.h"
#import <UDPieceTable/UDLinesDiffComputer.h>

/* Where each line of `lines` (a text cut at its line feeds) starts, as if
   the text ended in a line feed too: then every line ends in one, and the
   last's ends one past the text, where the next would start. */
static NSArray<NSNumber *> *MBULineStarts(NSArray<NSString *> *lines)
{
  NSMutableArray *starts = [NSMutableArray arrayWithCapacity:lines.count + 1];
  NSUInteger offset = 0;
  for (NSString *line in lines) {
    [starts addObject:@(offset)];
    offset += line.length + 1;
  }
  [starts addObject:@(offset)];
  return starts;
}

/* The offset of a line number (1-based); one past the last line, past the
   text and its imagined last line feed. */
static NSUInteger MBUOffsetOfLine(NSArray<NSNumber *> *starts, NSInteger line)
{
  NSInteger index = MAX(0, MIN((NSInteger)starts.count - 1, line - 1));
  return [starts[(NSUInteger)index] unsignedIntegerValue];
}

NSArray<UDTextModelEdit *> *MBUEditsToText(UDTextModel *model, NSString *text)
{
  NSString *old = [model getValue] ?: @"";
  if ([old isEqualToString:text]) return @[];
  NSArray *oldLines = [old componentsSeparatedByString:@"\n"];
  NSArray *newLines = [text componentsSeparatedByString:@"\n"];
  UDLinesDiff *diff = [UDLinesDiffComputer diffOfOriginalLines:oldLines
                                                 modifiedLines:newLines
                                          ignoreTrimWhitespace:NO
                                            maxComputationTime:0];
  NSArray *oldStarts = MBULineStarts(oldLines), *newStarts = MBULineStarts(newLines);
  NSUInteger length = old.length;
  NSMutableArray *edits = [NSMutableArray array];
  for (UDDetailedLineRangeMapping *change in diff.changes) {
    NSUInteger from = MBUOffsetOfLine(oldStarts, change.original.startLineNumber);
    NSUInteger to = MBUOffsetOfLine(oldStarts, change.original.endLineNumberExclusive);
    NSUInteger newFrom = MBUOffsetOfLine(newStarts, change.modified.startLineNumber);
    NSUInteger newTo = MBUOffsetOfLine(newStarts, change.modified.endLineNumberExclusive);
    /* The lines as the texts would be with their imagined line feeds. */
    NSString *lines = [[text stringByAppendingString:@"\n"] substringWithRange:NSMakeRange(newFrom, newTo - newFrom)];
    if (to > length) {
      /* Lines that end the text, which ends with no line feed of its own:
         the new lines' last feed is the imagined one; with no new lines,
         the feed before the old ones goes with them. */
      if (lines.length) {
        lines = [lines substringToIndex:lines.length - 1];
        if (from > length) lines = [@"\n" stringByAppendingString:lines];
      } else if (from > 0) {
        from -= 1;
      }
      from = MIN(from, length);
      to = length;
    }
    UDPosition start = [model getPositionAt:(NSInteger)from];
    UDPosition end = [model getPositionAt:(NSInteger)to];
    UDRange range = {start.line, start.column, end.line, end.column};
    [edits addObject:[[UDTextModelEdit alloc] initWithRange:range text:lines]];
  }
  return edits;
}

BOOL MBUWriteText(UDTextModel *model, NSString *text)
{
  NSArray *edits = MBUEditsToText(model, text);
  if (!edits.count) return NO;
  [model applyEdits:edits];
  return YES;
}
