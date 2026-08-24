# coredata-model.make - compile Xcode data models with FreeCoreData's momc
# as part of any gnustep-make project.
#
# Usage, in a project's GNUmakefile:
#
#     include $(GNUSTEP_MAKEFILES)/common.make
#
#     APP_NAME = MyApp
#     MyApp_OBJC_FILES = ...
#     MyApp_XCDATAMODELD_FILES = Model.xcdatamodeld
#
#     include $(GNUSTEP_MAKEFILES)/coredata-model.make
#     include $(GNUSTEP_MAKEFILES)/application.make
#
# Every <target>_XCDATAMODELD_FILES entry is compiled to the matching
# .momd bundle and added to that target's resources automatically;
# single-version <target>_XCDATAMODEL_FILES compile to bare .mom files.
# Set the model variables BEFORE including this file, and include this
# file BEFORE the target's {application,tool,framework,bundle}.make.
#
# The compiler is looked up as 'momc' on PATH; override with MOMC=...
# (the FreeCoreData test suite, for example, points it at the freshly
# built, uninstalled tool).

MOMC ?= momc

_CD_MODEL_TARGETS = $(FRAMEWORK_NAME) $(APP_NAME) $(TOOL_NAME) \
                    $(BUNDLE_NAME) $(LIBRARY_NAME) $(CTOOL_NAME)

define _cd_model_template
$(1)_COMPILED_MODELS = \
    $$(patsubst %.xcdatamodeld,%.momd,$$($(1)_XCDATAMODELD_FILES)) \
    $$(patsubst %.xcdatamodel,%.mom,$$($(1)_XCDATAMODEL_FILES))
$(1)_RESOURCE_FILES += $$($(1)_COMPILED_MODELS)
_CD_ALL_COMPILED_MODELS += $$($(1)_COMPILED_MODELS)
endef

$(foreach _cd_target,$(_CD_MODEL_TARGETS),\
    $(eval $(call _cd_model_template,$(_cd_target))))

# Models are recompiled on every build: a directory's own mtime does
# not change when a file inside it is edited, and Xcode's version names
# contain spaces ("Model 2.xcdatamodel"), which make cannot carry in a
# prerequisite list - while compiling a model takes milliseconds, going
# stale silently would cost an afternoon.
.PHONY: _cd-force-model-compile
_cd-force-model-compile:

%.momd: %.xcdatamodeld _cd-force-model-compile
	$(MOMC) $< $@

%.mom: %.xcdatamodel _cd-force-model-compile
	$(MOMC) $< $@

# Models compile before any target builds.
before-all:: $(_CD_ALL_COMPILED_MODELS)

after-clean::
	rm -rf $(_CD_ALL_COMPILED_MODELS)
