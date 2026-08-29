# ModelBuilder end-to-end tests (headless).  See README.md for the
# scenario catalogue and requirements (headless gnustep-back, patched
# libs-base, built CoreData framework in the tree).
ifeq ($(GNUSTEP_MAKEFILES),)
$(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang

TOOL_NAME = MBDocumentSmoke MBWindowProbe

MB_SOURCES = \
	../../ModelBuilder/MBDocument.m \
	../../ModelBuilder/MBEditors.m \
	../../ModelBuilder/MBWindowController.m \
	../../Tools/momc/CDModelCompiler.m \
	../../Tools/momc/CDModelSerializer.m \
	../../Tools/momc/CDModelMutator.m \
	../../Tools/momc/CDCodeGenerator.m \
	../../ModelBuilder/MBStepperTextField.m \
	../../ModelBuilder/ThirdParty/DMTabBar/DMTabBar/DMTabBar/DMTabBar.m \
	../../ModelBuilder/ThirdParty/DMTabBar/DMTabBar/DMTabBar/DMTabBarItem.m \
	../../ModelBuilder/ThirdParty/JUInspectorView/Source/JUInspectorBaseView.m \
	../../ModelBuilder/ThirdParty/JUInspectorView/Source/JUInspectorView.m \
	../../ModelBuilder/ThirdParty/JUInspectorView/Source/JUInspectorViewContainer.m \
	../../ModelBuilder/ThirdParty/JUInspectorView/Source/JUInspectorViewHeader.m

MBDocumentSmoke_OBJC_FILES = MBDocumentSmoke.m $(MB_SOURCES)
MBWindowProbe_OBJC_FILES = MBWindowProbe.m $(MB_SOURCES)

ADDITIONAL_INCLUDE_DIRS += -I../.. -I../../Tools/momc -I../../ModelBuilder \
	-I../../ModelBuilder/ThirdParty/DMTabBar/DMTabBar/DMTabBar \
	-I../../ModelBuilder/ThirdParty/JUInspectorView/Source

FRAMEWORK_BUILD_DIR = $(CURDIR)/../../CoreData.framework/Versions/Current

MBDocumentSmoke_OBJC_LIBS += -lCoreData -lgnustep-gui
MBWindowProbe_OBJC_LIBS += -lCoreData -lgnustep-gui
ADDITIONAL_LIB_DIRS += -L$(FRAMEWORK_BUILD_DIR) -L$(GNUSTEP_SYSTEM_LIBRARIES)

ADDITIONAL_OBJCFLAGS += -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 \
	-fconstant-string-class=NSConstantString -fobjc-exceptions

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/tool.make
-include GNUmakefile.postamble

# The window probe needs an .app-shaped wrapper: GNUstep's NSBundle
# resolves a Resources/ subdirectory (where the nib lives) only for
# app-wrapper paths, not for a bare tool directory.
after-all::
	@wrap="$(GNUSTEP_OBJ_DIR)/MBWindowProbe.app"; \
	mkdir -p "$$wrap/Resources"; \
	cp -f "$(GNUSTEP_OBJ_DIR)/MBWindowProbe" "$$wrap/"; \
	cp -f ../../ModelBuilder/MBDocumentWindow.xib "$$wrap/Resources/"

RUN_ENV = LD_LIBRARY_PATH="$(FRAMEWORK_BUILD_DIR):$(GNUSTEP_LOCAL_LIBRARIES):$(GNUSTEP_SYSTEM_LIBRARIES):$$LD_LIBRARY_PATH"

.PHONY: check
check::
	$(RUN_ENV) "$(GNUSTEP_OBJ_DIR)/MBDocumentSmoke"
	$(RUN_ENV) "$(GNUSTEP_OBJ_DIR)/MBWindowProbe.app/MBWindowProbe"

# gnustep-make mirrors ../../ source paths beside obj/ when compiling
# out-of-directory sources; sweep those artifacts too.
clean::
	rm -rf ModelBuilder Tools
