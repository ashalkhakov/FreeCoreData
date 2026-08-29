# ModelBuilder — document-based .xcdatamodeld editor.
# Lives at the FreeCoreData repo root (sibling of Tools/momc and
# coredata-model.make). Requires gnustep-gui + Foundation (NSXMLDocument).
# CoreData is not required to edit the XML.
ifeq ($(GNUSTEP_MAKEFILES),)
$(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang

APP_NAME = ModelBuilder
ModelBuilder_OBJC_FILES = main.m MBDocument.m MBEditors.m MBWindowController.m \
	../Tools/momc/CDModelCompiler.m ../Tools/momc/CDModelSerializer.m \
	../Tools/momc/CDModelMutator.m \
	../Tools/momc/CDCodeGenerator.m \
	MBStepperTextField.m \
	ThirdParty/DMTabBar/DMTabBar/DMTabBar/DMTabBar.m \
	ThirdParty/DMTabBar/DMTabBar/DMTabBar/DMTabBarItem.m \
	ThirdParty/JUInspectorView/Source/JUInspectorBaseView.m \
	ThirdParty/JUInspectorView/Source/JUInspectorView.m \
	ThirdParty/JUInspectorView/Source/JUInspectorViewContainer.m \
	ThirdParty/JUInspectorView/Source/JUInspectorViewHeader.m
ModelBuilder_RESOURCE_FILES = MainMenu.xib MBDocumentWindow.xib Info-gnustep.plist
ModelBuilder_MAIN_MODEL_FILE = MainMenu.xib
ModelBuilder_APPLICATION_ICON =

# Repo-root layout: headers/framework sit one directory up.
ModelBuilder_INCLUDE_DIRS = -I.. -I../Tools/momc \
	-IThirdParty/DMTabBar/DMTabBar/DMTabBar \
	-IThirdParty/JUInspectorView/Source
ModelBuilder_OBJC_LIBS += -lCoreData
ADDITIONAL_LIB_DIRS += -L$(CURDIR)/../CoreData.framework/Versions/Current \
	-L$(GNUSTEP_SYSTEM_LIBRARIES)

ADDITIONAL_OBJCFLAGS += -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 \
	-fconstant-string-class=NSConstantString -fobjc-exceptions

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/application.make
-include GNUmakefile.postamble

after-all::
	@dst="$(GNUSTEP_OBJ_DIR)/$(APP_NAME).app/Resources"; \
	if [ ! -d "$$dst" ]; then dst="./$(APP_NAME).app/Resources"; fi; \
	mkdir -p "$$dst"; \
	cp -f MainMenu.xib MBDocumentWindow.xib Info-gnustep.plist "$$dst/"
