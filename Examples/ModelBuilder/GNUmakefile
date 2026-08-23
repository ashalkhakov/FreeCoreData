# ModelBuilder — document-based .xcdatamodeld editor.
# Requires gnustep-gui + Foundation (NSXMLDocument). CoreData is not required
# to edit the XML; it is linked when present so the app sits next to FreeCoreData.
ifeq ($(GNUSTEP_MAKEFILES),)
$(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang

APP_NAME = ModelBuilder
ModelBuilder_OBJC_FILES = main.m MBModel.m MBDocument.m MBWindowController.m
ModelBuilder_RESOURCE_FILES = MainMenu.xib MBDocument.xib Info-gnustep.plist
ModelBuilder_MAIN_MODEL_FILE = MainMenu.xib
ModelBuilder_APPLICATION_ICON =

ADDITIONAL_OBJCFLAGS += -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 \
	-fconstant-string-class=NSConstantString -fobjc-exceptions

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/application.make
-include GNUmakefile.postamble

after-all::
	@dst="$(GNUSTEP_OBJ_DIR)/$(APP_NAME).app/Resources"; \
	if [ ! -d "$$dst" ]; then dst="./$(APP_NAME).app/Resources"; fi; \
	mkdir -p "$$dst"; \
	cp -f MainMenu.xib MBDocument.xib Info-gnustep.plist "$$dst/"; \
	if [ -f Info-gnustep.plist ]; then cp -f Info-gnustep.plist "$$dst/Info-gnustep.plist"; fi
