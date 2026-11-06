# ModelBuilderTests -- ModelBuilder's document and mapping layers, its
# editors, and its two windows loaded from their XIBs and driven as a user
# would (MBDocumentTests, MBEditorsTests, MBModelWindowTests,
# MBMappingEditorTests, MBMappingWindowTests).  An XCTest bundle holding
# ModelBuilder's sources and XIBs, run by xctest; the windows need a
# display (the top GNUmakefile's check runs it under xvfb-run when there
# is none) and the CoreData framework built in the tree.
ifeq ($(GNUSTEP_MAKEFILES),)
$(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang

BUNDLE_NAME = ModelBuilderTests
BUNDLE_EXTENSION = .bundle
ModelBuilderTests_NEEDS_GUI = yes
ModelBuilderTests_PRINCIPAL_CLASS = XCTestCase

MODELBUILDER_DIR = ../../ModelBuilder
include $(MODELBUILDER_DIR)/files.make

ModelBuilderTests_OBJC_FILES = \
	MBDocumentTests.m \
	MBEditorsTests.m \
	MBModelWindowTests.m \
	MBMappingEditorTests.m \
	MBMappingWindowTests.m \
	$(addprefix $(MODELBUILDER_DIR)/,$(MODELBUILDER_OBJC_FILES))

# The windows' and parts' XIBs: the bundle is where its classes look for them.
ModelBuilderTests_RESOURCE_FILES = $(addprefix $(MODELBUILDER_DIR)/,$(MODELBUILDER_RESOURCE_FILES))

ADDITIONAL_INCLUDE_DIRS += $(MODELBUILDER_INCLUDE_DIRS)

FRAMEWORK_BUILD_DIR = $(firstword $(wildcard $(CURDIR)/../../CoreData.framework/Versions/Current) $(CURDIR)/../../CoreData.framework)

ModelBuilderTests_BUNDLE_LIBS += -lCoreData -lXCTest -lgnustep-gui
ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR) -L$(GNUSTEP_SYSTEM_LIBRARIES)

ADDITIONAL_OBJCFLAGS += -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 \
	-fconstant-string-class=NSConstantString -fobjc-exceptions

XCTEST ?= xctest

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/bundle.make
-include GNUmakefile.postamble

# The bundle has ten minutes, and what it prints goes to a file of which
# the last lines are shown: a test that waits for an event that never
# comes fails with what it said last, rather than holding the build (or
# flooding its log) until CI gives up on it; and a daemon a test starts
# (gpbs, gdnc), which inherits where the output goes, holds no CI step's
# pipe open.
RUN_ENV = LD_LIBRARY_PATH="$(FRAMEWORK_BUILD_DIR):$(GNUSTEP_LOCAL_LIBRARIES):$(GNUSTEP_SYSTEM_LIBRARIES):$$LD_LIBRARY_PATH" PATH="$(FRAMEWORK_BUILD_DIR):$(GNUSTEP_LOCAL_LIBRARIES):$(GNUSTEP_SYSTEM_LIBRARIES):$$PATH"

.PHONY: check
check:: $(BUNDLE_NAME)$(BUNDLE_EXTENSION)
	@$(RUN_ENV) timeout --kill-after=10 600 $(XCTEST) "$(BUNDLE_NAME)$(BUNDLE_EXTENSION)" > "$(BUNDLE_NAME).log" 2>&1; \
	status=$$?; grep -v "unknown control size\|unknown custom color space\|_NET_WORKAREA\|given negative width\|IBUserDefinedRuntimeAttribute5" \
	  "$(BUNDLE_NAME).log" | tail -n 150; \
	[ $$status = 0 ] || echo "== $(BUNDLE_NAME) exited $$status"; exit $$status
