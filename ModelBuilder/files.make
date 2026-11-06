# ModelBuilder's sources and XIBs, but the application's own (main.m, the
# app delegate, the updater and MainMenu.xib): what the app, its tests
# (Tests/ModelBuilder) and UDCode's Core Data extension (UDCodeExtension)
# compile and carry.  Paths are this directory's; an includer adds its
# prefix (MODELBUILDER_DIR).
MODELBUILDER_OBJC_FILES = \
	MBDocument.m MBModelEditor.m MBModelCommands.m MBEditors.m \
	MBWindowController.m MBWindowSupport.m \
	MBSourceListViewController.m MBDetailViewController.m MBInspectorViewController.m \
	MBMappingDocument.m MBMappingEditor.m MBMappingEditors.m MBMappingWindowController.m \
	MBMappingSourceListViewController.m MBMappingDetailViewController.m MBMappingInspectorViewController.m \
	MBNewMappingController.m MBStepperTextField.m \
	../Tools/momc/CDModelCompiler.m ../Tools/momc/CDModelSerializer.m \
	../Tools/momc/CDModelMutator.m ../Tools/momc/CDCodeGenerator.m \
	../Tools/mapc/CDMappingCompiler.m ../Tools/mapc/CDMappingSerializer.m \
	ThirdParty/DMTabBar/DMTabBar/DMTabBar/DMTabBar.m \
	ThirdParty/DMTabBar/DMTabBar/DMTabBar/DMTabBarItem.m \
	ThirdParty/JUInspectorView/Source/JUInspectorBaseView.m \
	ThirdParty/JUInspectorView/Source/JUInspectorView.m \
	ThirdParty/JUInspectorView/Source/JUInspectorViewContainer.m \
	ThirdParty/JUInspectorView/Source/JUInspectorViewHeader.m
MODELBUILDER_RESOURCE_FILES = \
	MBDocumentWindow.xib MBSourceList.xib MBDetail.xib MBInspector.xib \
	MBMappingWindow.xib MBMappingSourceList.xib MBMappingDetail.xib MBMappingInspector.xib \
	MBNewMappingPanel.xib
MODELBUILDER_INCLUDE_DIRS = -I$(MODELBUILDER_DIR)/.. -I$(MODELBUILDER_DIR)/../Tools/momc -I$(MODELBUILDER_DIR)/../Tools/mapc \
	-I$(MODELBUILDER_DIR) \
	-I$(MODELBUILDER_DIR)/ThirdParty/DMTabBar/DMTabBar/DMTabBar \
	-I$(MODELBUILDER_DIR)/ThirdParty/JUInspectorView/Source
