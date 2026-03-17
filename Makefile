# Makefile for SData

GPR_FILE = sdata.gpr
# Prefer the Alire-managed gprbuild if present, fall back to system gprbuild.
ALIRE_GPRBUILD := /home/jries/.local/share/alire/toolchains/gprbuild_25.0.1_9a2e6cfb/bin/gprbuild
GPRBUILD_ALIRE_PATH := $(if $(wildcard $(ALIRE_GPRBUILD)),$(ALIRE_GPRBUILD),$(shell which gprbuild 2>/dev/null))

# GPR_PROJECT_PATH: tells gprbuild where to find dependency .gpr files.
# If already set in the environment (e.g. by the RPM spec), use that.
# Otherwise auto-detect from sibling Alire-managed directories.
DEP_BASE := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
_ZIPADA_DIR    := $(firstword $(wildcard $(DEP_BASE)/zipada_*))
_XMLADA_DIR    := $(firstword $(wildcard $(DEP_BASE)/xmlada_*))
_MATHPAQS_DIR  := $(firstword $(wildcard $(DEP_BASE)/mathpaqs_*))
_SCIADA_DIR    := $(firstword $(wildcard $(DEP_BASE)/sciada_*))
_LOCAL_GPR_PATH := $(_ZIPADA_DIR):$(_XMLADA_DIR)/dom:$(_XMLADA_DIR)/input_sources:$(_MATHPAQS_DIR):$(_SCIADA_DIR)
export GPR_PROJECT_PATH ?= $(_LOCAL_GPR_PATH)
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
INSTALL_DIR = $(DESTDIR)$(BINDIR)

.PHONY: all build clean run check install srpm

all: build

build:
	$(GPRBUILD_ALIRE_PATH) -P $(GPR_FILE)

run: build
	./bin/sdata tests/test1.cmd

check: build
	@echo "Running tests..."
	@for f in tests/*.cmd; do \
		base=$$(basename $$f .cmd); \
		exp="tests/expected/$$base.out"; \
		flags="tests/$$base.flags"; \
		extra_flags=""; \
		if [ -f "$$flags" ]; then extra_flags=$$(cat "$$flags"); fi; \
		echo -n "Testing $$f... "; \
		./bin/sdata $$extra_flags $$f > tests/$$base.tmp 2>&1; \
		if [ $$? -ne 0 ]; then \
			echo "FAILED (Execution Error)"; \
			rm tests/$$base.tmp; \
			exit 1; \
		fi; \
		if [ -f "$$exp" ]; then \
			diff -u "$$exp" tests/$$base.tmp > tests/$$base.diff; \
			if [ $$? -eq 0 ]; then \
				echo "PASSED"; \
				rm tests/$$base.tmp tests/$$base.diff; \
			else \
				echo "FAILED (Output Mismatch)"; \
				cat tests/$$base.diff; \
				rm tests/$$base.tmp tests/$$base.diff; \
				exit 1; \
			fi; \
		else \
			echo "PASSED (No expected output file found)"; \
			rm tests/$$base.tmp; \
		fi; \
	done
	@echo "All tests passed."

srpm: clean
	@echo "Creating source tarball..."
	@{ \
		if [ -z "$$(git status --untracked-files=no --porcelain)" ]; then \
			git archive --format=tar --prefix=sdata-0.1/ HEAD | gzip > sdata-0.1.tar.gz; \
		else \
			echo "ERROR: Working directory is not clean. Please commit changes before creating a source package."; \
			exit 1; \
		fi \
	}
	@echo "Building SRPM..."
	@mkdir -p rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
	@mv sdata-0.1.tar.gz rpmbuild/SOURCES/
	@cp sdata.spec rpmbuild/SPECS/
	@# Copy vendored Ada library tarballs from their canonical location.
	@TARBALL_DIR="$(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../Data/tarballs)"; \
	 for tb in zipada-61.0.0.tar.gz xmlada-26.0.0.tar.gz mathpaqs-20260205.0.0.tar.gz sciada-0.4.0.tar.gz; do \
	   if [ ! -f "$$TARBALL_DIR/$$tb" ]; then \
	     echo "ERROR: dependency tarball not found: $$TARBALL_DIR/$$tb"; exit 1; \
	   fi; \
	   cp "$$TARBALL_DIR/$$tb" rpmbuild/SOURCES/; \
	 done
	@rpmbuild -bs rpmbuild/SPECS/sdata.spec --define "_topdir %(pwd)/rpmbuild"
	@mv rpmbuild/SRPMS/sdata-0.1-1.src.rpm .
	@rm -rf rpmbuild
	@echo "SRPM created: sdata-0.1-1.src.rpm"


install: build
	install -d $(INSTALL_DIR)
	install -m 755 bin/sdata $(INSTALL_DIR)/sdata

clean:
	@echo "Cleaning build artifacts..."
	rm -rf obj bin tests/*.tmp tests/*.diff
