# The Core Data extension's tests (an XCTest bundle; tools-xctest), against
# UDCode's SDK installed: the extension's sources and ModelBuilder's compiled
# in (their XIBs found in this bundle, as in ModelBuilder.bundle), UDCodeKit's
# document and text model linked.
#
#   make            build the bundle
#   make run-tests  build and run it (under xvfb-run where there is no display)
include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang

BUNDLE_NAME = MBUTests
MBUTests_STANDARD_INSTALL = no
MBUTests_NEEDS_GUI = yes
MBUTests_PRINCIPAL_CLASS = XCTestCase

MODELBUILDER_DIR = ../../ModelBuilder
include $(MODELBUILDER_DIR)/files.make
MBUTests_OBJC_FILES = \
	MBUTests.m \
	../MBUExtension.m \
	../MBUEditorView.m \
	../MBUModelEditorViewController.m \
	../MBUMappingEditorViewController.m \
	../MBUTextEdits.m \
	$(addprefix $(MODELBUILDER_DIR)/,$(MODELBUILDER_OBJC_FILES))
MBUTests_RESOURCE_FILES = \
	../MBUModelEditor.xib \
	../MBUMappingEditor.xib \
	../MBUEditorMenus.xib \
	$(addprefix $(MODELBUILDER_DIR)/,$(MODELBUILDER_RESOURCE_FILES))
MBUTests_INCLUDE_DIRS = -I.. $(MODELBUILDER_INCLUDE_DIRS)
MBUTests_OBJCFLAGS += -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 \
	-fconstant-string-class=NSConstantString -fobjc-exceptions
FRAMEWORK_BUILD_DIR = $(firstword $(wildcard $(CURDIR)/../../CoreData.framework/Versions/Current) $(CURDIR)/../../CoreData.framework)
ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR)
MBUTests_BUNDLE_LIBS += -lCoreData -lUDCodeKit -lUDPieceTable -lLSPKit -lXCTest -ldispatch

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest
TEST_TIMEOUT ?= 600

# What it prints goes to a file, of which the end is shown: a daemon a test
# starts (GNUstep's gpbs, gdnc) inherits where the output goes, and one
# holding the output's pipe keeps a CI step that reads it from ending.
.PHONY: run-tests
run-tests: all
	@LD_LIBRARY_PATH="$(FRAMEWORK_BUILD_DIR):$$LD_LIBRARY_PATH" PATH="$(FRAMEWORK_BUILD_DIR):$$PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle > $(BUNDLE_NAME).log 2>&1; \
	status=$$?; grep -v "unknown control size\|unknown custom color space\|_NET_WORKAREA\|given negative width\|IBUserDefinedRuntimeAttribute5" \
	  $(BUNDLE_NAME).log | tail -n 150; \
	[ $$status = 0 ] || echo "== $(BUNDLE_NAME) exited $$status"; exit $$status
