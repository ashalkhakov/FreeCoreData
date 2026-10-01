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
# Code generation, as Xcode does it at build time: with
#
#     MyApp_COREDATA_CODEGEN = yes
#
# the target's models' entities whose Codegen is Class Definition or
# Category/Extension get their NSManagedObject sources generated before
# the target builds -- ClassName+CoreDataClass.h/m and
# ClassName+CoreDataProperties.h/m, or the properties alone for a
# category, whose class the project writes -- into
# $(GNUSTEP_OBJ_DIR)/CoreDataGenerated/<target>, which is put on the
# target's include path (#import "Book+CoreDataProperties.h") and
# compiled with it. Opt-in, because Xcode marks new entities Class
# Definition, and a project that keeps its classes by hand would get
# them twice. A file is rewritten only when the model changes it.
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

# The generated sources are known only once momc has run, after make has
# read the target's file list, so the target compiles one file of a known
# name that imports them all.
define _cd_codegen_template
ifeq ($$(strip $$($(1)_COREDATA_CODEGEN)),yes)
$(1)_CODEGEN_DIR = $$(GNUSTEP_OBJ_DIR)/CoreDataGenerated/$(1)
$(1)_OBJC_FILES += $$($(1)_CODEGEN_DIR)/$(1)+CoreDataGenerated.m
$(1)_INCLUDE_DIRS += -I$$($(1)_CODEGEN_DIR)
_CD_CODEGEN_RULES += _cd-codegen-$(1)

.PHONY: _cd-codegen-$(1)
_cd-codegen-$(1): _cd-codegen
	@dir='$$($(1)_CODEGEN_DIR)'; tmp="$$$$dir.tmp"; \
	rm -rf "$$$$tmp"; mkdir -p "$$$$tmp" "$$$$dir"; \
	for model in $$($(1)_XCDATAMODELD_FILES) $$($(1)_XCDATAMODEL_FILES); do \
	  $$(MOMC) --codegen "$$$$model" "$$$$tmp" >/dev/null || exit 1; \
	done; \
	{ echo '/* Every source momc generated for $(1): compiled as one. */'; \
	  for source in "$$$$tmp"/*.m; do \
	    [ -e "$$$$source" ] && echo "#import \"$$$${source##*/}\""; \
	  done; true; } > "$$$$tmp.m"; \
	mv "$$$$tmp.m" "$$$$tmp/$(1)+CoreDataGenerated.m"; \
	for file in "$$$$tmp"/*; do \
	  cmp -s "$$$$file" "$$$$dir/$$$${file##*/}" || cp "$$$$file" "$$$$dir/"; \
	done; \
	for file in "$$$$dir"/*; do \
	  [ -e "$$$$tmp/$$$${file##*/}" ] || rm -f "$$$$file"; \
	done; \
	rm -rf "$$$$tmp"
endif
endef

# This file is documented to be included BEFORE the target's
# {application,tool,framework,bundle}.make - but in that position our
# first explicit rule would become make's default goal, so a plain
# 'make' would stop after the fragment's own rules and never build the
# target (reported by UDQuakeTools).  Save whatever default goal was in
# effect on entry and restore it below, falling back to gnustep-make's
# canonical 'all' (defined later by the target makefile - naming a
# not-yet-defined goal is fine).
_CD_SAVED_DEFAULT_GOAL := $(.DEFAULT_GOAL)
# Saved before the codegen template is expanded, not after: that
# template's own rule would otherwise be what gets saved and restored,
# which is the same bug one step further along.

$(foreach _cd_target,$(_CD_MODEL_TARGETS),\
    $(eval $(call _cd_codegen_template,$(_cd_target))))


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

# What every generation waits for: a project whose momc is built in the
# tree makes this depend on it.
.PHONY: _cd-codegen
_cd-codegen:

# Models compile, and their classes are generated, before any target builds.
before-all:: $(_CD_ALL_COMPILED_MODELS) $(_CD_CODEGEN_RULES)

after-clean::
	rm -rf $(_CD_ALL_COMPILED_MODELS) $(GNUSTEP_OBJ_DIR)/CoreDataGenerated

# Restore the default goal (see comment above _CD_SAVED_DEFAULT_GOAL).
ifeq ($(_CD_SAVED_DEFAULT_GOAL),)
.DEFAULT_GOAL := all
else
.DEFAULT_GOAL := $(_CD_SAVED_DEFAULT_GOAL)
endif
