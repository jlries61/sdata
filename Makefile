# Makefile for SData

GPR_FILE = sdata.gpr
# Prefer the Alire-managed gprbuild if present, fall back to system gprbuild.
ALIRE_GPRBUILD := /home/jries/.local/share/alire/toolchains/gprbuild_25.0.2.1_9a2e6cfb/bin/gprbuild
# Try Alire, then 'which', then default to 'gprbuild' and let the shell decide.
GPRBUILD_ALIRE_PATH := $(firstword $(wildcard $(ALIRE_GPRBUILD)) $(shell which gprbuild 2>/dev/null) gprbuild)

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

.PHONY: all build clean run check install srpm pkg

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
			git archive --format=tar --prefix=sdata-0.2.1/ HEAD | gzip > sdata-0.2.1.tar.gz; \
		else \
			echo "ERROR: Working directory is not clean. Please commit changes before creating a source package."; \
			exit 1; \
		fi \
	}
	@echo "Building SRPM..."
	@mkdir -p rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
	@mv sdata-0.2.1.tar.gz rpmbuild/SOURCES/
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
	@mv rpmbuild/SRPMS/sdata-0.2.1-1.src.rpm .
	@rm -rf rpmbuild
	@echo "SRPM created: sdata-0.2.1-1.src.rpm"

dsc: clean
	@echo "Creating Debian Source Package..."
	@TARBALL_DIR="$(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../Data/tarballs)"; \
	 CUR_DIR=$$(pwd); \
	 TEMP_DIR=$$(mktemp -d); \
	 BASE_DIR="sdata-0.2.1"; \
	 SRC_DIR="$$TEMP_DIR/$$BASE_DIR"; \
	 mkdir -p "$$SRC_DIR"; \
	 cp -r * "$$SRC_DIR/"; \
	 for tb in zipada-61.0.0.tar.gz xmlada-26.0.0.tar.gz mathpaqs-20260205.0.0.tar.gz sciada-0.4.0.tar.gz; do \
	   tar xzf "$$TARBALL_DIR/$$tb" -C "$$SRC_DIR/"; \
	 done; \
	 cd "$$TEMP_DIR" && tar czf "sdata_0.2.1.orig.tar.gz" "$$BASE_DIR"; \
	 cd "$$SRC_DIR" && dpkg-source -b .; \
	 mv "$$TEMP_DIR"/sdata_0.2.1* "$$CUR_DIR/" ; \
	 rm -rf "$$TEMP_DIR"
	@echo "Debian Source Package created (sdata_0.2.1-1.dsc, sdata_0.2.1.orig.tar.gz, etc.)"

slackware: clean
	@echo "Creating SlackBuild tarball..."
	@{ \
		if [ -z "$$(git status --untracked-files=no --porcelain)" ]; then \
			git archive --format=tar --prefix=sdata-0.2.1/ HEAD | gzip > sdata-0.2.1.tar.gz; \
		else \
			echo "ERROR: Working directory is not clean. Please commit changes before creating a source package."; \
			exit 1; \
		fi \
	}
	@TARBALL_DIR="$(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../Data/tarballs)"; \
	 CUR_DIR=$$(pwd); \
	 TEMP_DIR=$$(mktemp -d); \
	 cp sdata-0.2.1.tar.gz "$$TEMP_DIR/"; \
	 cp slackware/* "$$TEMP_DIR/"; \
	 for tb in zipada-61.0.0.tar.gz xmlada-26.0.0.tar.gz mathpaqs-20260205.0.0.tar.gz; do \
	   cp "$$TARBALL_DIR/$$tb" "$$TEMP_DIR/"; \
	 done; \
	 cd "$$TEMP_DIR" && tar czf sdata-0.2.1-slackbuild.tar.gz *; \
	 mv "$$TEMP_DIR/sdata-0.2.1-slackbuild.tar.gz" "$$CUR_DIR/"; \
	 rm -rf "$$TEMP_DIR"
	@echo "SlackBuild package created: sdata-0.2.1-slackbuild.tar.gz"


pkg: build
	@echo "Creating macOS installer package..."
	@TEMP_DIR=$$(mktemp -d); \
	 PKG_ROOT="$$TEMP_DIR/root"; \
	 mkdir -p "$$PKG_ROOT/usr/local/bin"; \
	 cp bin/sdata "$$PKG_ROOT/usr/local/bin/sdata"; \
	 chmod 755 "$$PKG_ROOT/usr/local/bin/sdata"; \
	 pkgbuild \
	   --root "$$PKG_ROOT" \
	   --identifier com.sdata.pkg \
	   --version 0.2.1 \
	   --install-location / \
	   sdata-0.2.1.pkg; \
	 rm -rf "$$TEMP_DIR"
	@echo "macOS package created: sdata-0.2.1.pkg"

install:
	@test -x bin/sdata || { echo "Error: bin/sdata not found. Run 'make' first."; exit 1; }
	install -d $(INSTALL_DIR)
	install -m 755 bin/sdata $(INSTALL_DIR)/sdata

clean:
	@echo "Cleaning build artifacts..."
	rm -rf obj bin tests/*.tmp tests/*.diff
