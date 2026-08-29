/* Repro for a gnustep-base NSXML memory corruption: adding or removing
   ATTRIBUTES on elements of a PARSED NSXMLDocument frees interior
   pointers of the document's libxml2 dictionary.

   Root cause: setTreeDoc() in Source/NSXMLNode.m adopts dictionary-
   interned strings for text and element nodes when a node moves
   between documents (detach creates a private document per detached
   node), but has no XML_ATTRIBUTE_NODE branch.  An attribute node
   detached directly - by -removeAttributeForName:, or by the subnode
   detach -dealloc performs - keeps its name interned in the OLD
   document's dictionary.  When the detached attribute is later freed,
   xmlFreeProp's dictionary-ownership check consults the attribute's
   (reassigned) doc, misses, and frees an interior pointer of the
   original document's dictionary: glibc aborts with
   "munmap_chunk(): invalid pointer" / "free(): invalid pointer",
   or the process segfaults at autorelease-pool drain, depending on
   heap layout.  Same hazard for comment/CDATA/PI content.

   Build (adjust paths to your prefix):
     clang nsxml-detached-attribute-repro.m -o repro \
       $(gnustep-config --objc-flags) $(gnustep-config --base-libs)
   Run:
     ./repro                  -> crashes without the patch, prints
                                 "drained OK" with it
     valgrind -q ./repro      -> two "Invalid free" reports without the
                                 patch (deterministic), clean with it

   Fix: patches/gnustep-base-nsxmlnode-detached-attribute-dict-strings.patch
   (adds XML_ATTRIBUTE_NODE and comment/CDATA/PI string adoption to
   setTreeDoc). */
#import <Foundation/Foundation.h>

int main(void)
{
  @autoreleasepool {
    NSError *error = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc]
        initWithXMLString:@"<model><entity name=\"Person\" a=\"1\"/></model>"
                  options:0
                    error:&error];
    NSXMLElement *el = [[[doc rootElement] elementsForName:@"entity"] firstObject];

    /* Detaches the parsed attribute node: its name stays interned in
       doc's dictionary. */
    [el removeAttributeForName:@"a"];

    /* A fresh attribute attached to a parsed element gets its name
       interned on attach; the detach in the wrapper teardown then hits
       the same hole. */
    [el addAttribute:[NSXMLNode attributeWithName:@"parentEntity"
                                      stringValue:@"X"]];

    NSLog(@"mutated: %@", [doc XMLString]);
  }
  /* Without the fix the pool drain above frees dictionary-invalid
     pointers; abort/segfault happens before or at this line. */
  puts("drained OK");
  return 0;
}
