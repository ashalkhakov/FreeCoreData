/* ModelBuilder — what the model window's parts and the mapping window
   share (see MBWindowSupport.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBWindowSupport.h"

NSSplitView *MBFirstSplitViewIn(NSView *view)
{
  for (NSView *subview in view.subviews)
    if ([subview isKindOfClass:[NSSplitView class]]) return (NSSplitView *)subview;
  return nil;
}

NSImage *MBFirstImageNamed(NSArray *names)
{
  for (NSString *name in names) {
    NSImage *image = [NSImage imageNamed:name];
    if (image) return image;
  }
  return nil;
}

void MBPresentModelError(NSError *error, NSString *title)
{
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = title;
  alert.informativeText = error.localizedDescription ?: @"Unknown error.";
  [alert runModal];
}

#pragma mark - Badges

/* Xcode-style circular letter badges, drawn once and cached.  The
   cache key carries the color, so the same letter can appear in
   different tints (Float "F" vs Fetch Request "F"). */
NSImage *MBBadgeImage(NSString *letters, CGFloat red, CGFloat green, CGFloat blue)
{
  static NSMutableDictionary *cache;
  if (!cache) cache = [NSMutableDictionary dictionary];
  NSString *key = [NSString stringWithFormat:@"%@|%.2f%.2f%.2f", letters, red, green, blue];
  NSImage *image = cache[key];
  if (image) return image;

  NSSize size = NSMakeSize(15, 15);
  image = [[NSImage alloc] initWithSize:size];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [image lockFocus];
  [[NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0] set];
  [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 14, 14)] fill];
  NSDictionary *attributes = @{
    NSFontAttributeName : [NSFont boldSystemFontOfSize:letters.length > 1 ? 7.0 : 9.0],
    NSForegroundColorAttributeName : [NSColor whiteColor],
  };
  NSSize textSize = [letters sizeWithAttributes:attributes];
  [letters drawAtPoint:NSMakePoint((size.width - textSize.width) / 2.0,
                                   (size.height - textSize.height) / 2.0)
        withAttributes:attributes];
  [image unlockFocus];
#pragma clang diagnostic pop
  cache[key] = image;
  return image;
}

/* Badge tints (muted, roughly Xcode's palette). */
NSImage *MBAttributeBadge(NSString *letters) { return MBBadgeImage(letters, 0.47, 0.53, 0.64); }
NSImage *MBEntityBadge(void)        { return MBBadgeImage(@"E", 0.36, 0.49, 0.72); }
NSImage *MBRelationshipBadge(void)  { return MBBadgeImage(@"R", 0.32, 0.60, 0.53); }
NSImage *MBFetchBadge(void)         { return MBBadgeImage(@"F", 0.58, 0.44, 0.72); }
NSImage *MBConfigurationBadge(void) { return MBBadgeImage(@"C", 0.78, 0.57, 0.31); }

NSString *MBAttributeBadgeLetters(NSAttributeDescription *attribute)
{
  switch (attribute.attributeType) {
    case NSStringAttributeType:        return @"S";
    case NSBooleanAttributeType:       return @"B";
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:     return @"I";
    case NSFloatAttributeType:         return @"F";
    case NSDoubleAttributeType:        return @"D";
    case NSDecimalAttributeType:       return @"Dc";
    case NSDateAttributeType:          return @"Dt";
    case NSBinaryDataAttributeType:    return @"Bn";
    case NSUUIDAttributeType:          return @"U";
    case NSURIAttributeType:           return @"Ur";
    case NSTransformableAttributeType: return @"T";
    default:                           return @"?";
  }
}

