include $(GNUSTEP_MAKEFILES)/common.make

# UDCode's Core Data extension (docs/UDCODE.md): ModelBuilder.bundle,
# ModelBuilder's editors in UDCode tabs. Built against UDCode's SDK (its
# udcodekit archive, .github/pins.env's UDCODEKIT_VERSION) installed on a
# GNUstep stack; the top GNUmakefile builds it only where that SDK is.
# ModelBuilder's sources and XIBs are compiled in (ModelBuilder/files.make);
# the CoreData framework's library goes beside its binary.
# Scripts/udcx.sh packages it, its libraries inside it.
CC = clang
OBJC = clang

BUNDLE_NAME = ModelBuilder
BUNDLE_EXTENSION = .bundle
ModelBuilder_PRINCIPAL_CLASS = MBUExtension
ModelBuilder_NEEDS_GUI = yes
ModelBuilder_STANDARD_INSTALL = no

MODELBUILDER_DIR = ../ModelBuilder
include $(MODELBUILDER_DIR)/files.make
ModelBuilder_OBJC_FILES = \
	MBUExtension.m \
	MBUEditorView.m \
	MBUModelEditorViewController.m \
	MBUMappingEditorViewController.m \
	MBUTextEdits.m \
	$(addprefix $(MODELBUILDER_DIR)/,$(MODELBUILDER_OBJC_FILES))
ModelBuilder_RESOURCE_FILES = \
	Resources/LanguageInfo.plist \
	MBUModelEditor.xib \
	MBUMappingEditor.xib \
	MBUEditorMenus.xib \
	$(addprefix $(MODELBUILDER_DIR)/,$(MODELBUILDER_RESOURCE_FILES))
ModelBuilder_INCLUDE_DIRS = $(MODELBUILDER_INCLUDE_DIRS)
ModelBuilder_OBJCFLAGS += -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 \
	-fconstant-string-class=NSConstantString -fobjc-exceptions
# The CoreData framework built in the tree, whose library the package puts
# beside the binary.
ModelBuilder_LIB_DIRS += -L../CoreData.framework/Versions/Current -L../CoreData.framework
# Its own library: found from where the binary is. UDCode's own (UDCodeKit,
# GNUstep's) are the running UDCode's: on Linux left for it, as UDCode's own
# plug-ins leave them; a Windows DLL is linked against all it uses.
ModelBuilder_BUNDLE_LIBS += -lCoreData -ldispatch
ifneq ($(OS),Windows_NT)
ModelBuilder_LDFLAGS += -Wl,-rpath,'$$ORIGIN'
else
ModelBuilder_BUNDLE_LIBS += -lUDCodeKit -lUDPieceTable -lLSPKit -lgnustep-gui -lgnustep-base -lobjc
endif

include $(GNUSTEP_MAKEFILES)/bundle.make
