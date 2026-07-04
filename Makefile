# Makefile for SData

VERSION          := 0.13.0
ZIPADA_VERSION      := 61.0.0
XMLADA_VERSION      := 26.0.0
MATHPAQS_VERSION    := 20260205.0.0
SQLITE3_TARBALL     := ada_sqlite3_0.1.1_2edbcebd

# Path to the sibling sdata-core checkout for packaging targets.
SDATA_CORE_REPO     := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../sdata-core)

# Bundled sdata-core version, derived from the sibling checkout's alire.toml so
# it can never drift out of sync.  Only used by the packaging targets, which
# already require SDATA_CORE_REPO to exist; the lookup is silenced (2>/dev/null)
# and resolves to empty in contexts where the sibling is absent — e.g. inside
# an unpacked source tarball during 'make build' from the SRPM — which is
# harmless since 'build' never references this variable.  Keep
# %global sdata_core_version in sdata.spec matching this value.
SDATA_CORE_VERSION  := $(shell sed -n 's/^version *= *"\([^"]*\)".*/\1/p' $(SDATA_CORE_REPO)/alire.toml 2>/dev/null | head -1)

GPR_FILE = sdata.gpr
# Use GPRBUILD from the environment or command line if set; otherwise detect
# from PATH.  When working with an Alire-managed toolchain, run 'alr build'
# directly, or ensure the toolchain is on PATH via 'eval $(alr printenv)'.
#
# When alr is available, build via 'alr exec -- gprbuild' so that alire
# manages GPR_PROJECT_PATH for all transitive dependencies (including
# sdata-core and its deps).  Fall back to raw gprbuild for packaging builds
# where GPR_PROJECT_PATH is provided externally (e.g. RPM spec).
ALR      := $(firstword $(shell which alr 2>/dev/null))
GPRBUILD ?= $(firstword $(shell which gprbuild 2>/dev/null) gprbuild)
# If GPR_PROJECT_PATH was supplied by the calling environment (e.g. by the
# RPM/Debian/Slackware spec), the caller has already wired in every dependency
# path and 'alr exec' must NOT be invoked — alire would try to resolve the
# alire.toml path pin to ../sdata-core, which doesn't exist in a packaging
# BUILD directory.  In that case, fall through to bare gprbuild.
ifeq ($(origin GPR_PROJECT_PATH),environment)
  BUILD_CMD = $(GPRBUILD) -P $(GPR_FILE)
else ifneq ($(ALR),)
  BUILD_CMD = $(ALR) exec -- $(GPRBUILD) -P $(GPR_FILE)
else
  BUILD_CMD = $(GPRBUILD) -P $(GPR_FILE)
endif
# GNU coreutils 'timeout' is 'gtimeout' on macOS/MacPorts; fall back to plain
# 'timeout' (Linux) if 'gtimeout' is not found.
TIMEOUT  := $(firstword $(shell which gtimeout 2>/dev/null) timeout)

# GPR_PROJECT_PATH: tells gprbuild where to find dependency .gpr files.
# If already set in the environment (e.g. by the RPM spec), use that.
# Otherwise auto-detect from the sibling source directories in the parent.
#
# Note: these sibling directories (zipada_*, xmlada_*, mathpaqs_*) are the
# library sources used for packaging targets (srpm, dsc, slackware) where
# alr may not be available.  They are separate from the copies that
# 'alr build' manages in ~/.local/share/alire/builds/ -- both paths use
# the same library versions, they are just physically independent.
DEP_BASE := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
_ZIPADA_DIR    := $(firstword $(wildcard $(DEP_BASE)/zipada_*))
_XMLADA_DIR    := $(firstword $(wildcard $(DEP_BASE)/xmlada_*))
_MATHPAQS_DIR  := $(firstword $(wildcard $(DEP_BASE)/mathpaqs_*))
_SQLITE3_DIR   := $(firstword $(wildcard $(DEP_BASE)/ada_sqlite3_*))
_SDATA_CORE_DIR := $(DEP_BASE)/sdata-core
_LOCAL_GPR_PATH := $(_ZIPADA_DIR):$(_XMLADA_DIR)/dom:$(_XMLADA_DIR)/input_sources:$(_MATHPAQS_DIR):$(_SQLITE3_DIR):$(_SDATA_CORE_DIR)
export GPR_PROJECT_PATH ?= $(_LOCAL_GPR_PATH)
PREFIX ?= /usr/local
BINDIR  = $(PREFIX)/bin
MANDIR  = $(PREFIX)/share/man
DOCDIR  = $(PREFIX)/share/doc/sdata
INSTALL_DIR  = $(DESTDIR)$(BINDIR)
MAN1_DIR     = $(DESTDIR)$(MANDIR)/man1
DOC_DIR      = $(DESTDIR)$(DOCDIR)

.PHONY: all build clean run check fuzz-corpus gnatcheck complexity-check install srpm pkg msi \
        sdata-core-tarball

all: build

build:
	$(BUILD_CMD)

run: build
	@if [ -z "$(FILE)" ]; then \
		echo "Error: please specify a script to run with FILE=<path>"; \
		echo "Usage: make run FILE=tests/test1.cmd"; \
		exit 1; \
	fi
	./bin/sdata $(FILE)

check: build
	@[ -x bin/csv_unit_test ] || $(BUILD_CMD)
	@[ -x bin/sdata_unit_test ] || $(BUILD_CMD)
	@echo "Running unit tests..."
	@$(TIMEOUT) 30 ./bin/csv_unit_test; \
	 if [ $$? -ne 0 ]; then \
	   echo "Unit tests FAILED"; exit 1; \
	 fi
	@$(TIMEOUT) 30 ./bin/sdata_unit_test; \
	 if [ $$? -ne 0 ]; then \
	   echo "Unit tests FAILED"; exit 1; \
	 fi
	@[ -x bin/evaluator_unit_test ] || $(BUILD_CMD)
	@$(TIMEOUT) 30 ./bin/evaluator_unit_test; \
	 if [ $$? -ne 0 ]; then \
	   echo "Unit tests FAILED"; exit 1; \
	 fi
	@[ -x bin/file_io_unit_test ] || $(BUILD_CMD)
	@$(TIMEOUT) 30 ./bin/file_io_unit_test; \
	 if [ $$? -ne 0 ]; then \
	   echo "Unit tests FAILED"; exit 1; \
	 fi
	@[ -x bin/interpreter_unit_test ] || $(BUILD_CMD)
	@$(TIMEOUT) 30 ./bin/interpreter_unit_test; \
	 if [ $$? -ne 0 ]; then \
	   echo "Unit tests FAILED"; exit 1; \
	 fi
	@echo ""
	@echo "Running tests..."
	@#  Generate the SUBMIT depth-limit chain (gitignored; see submit_depth_test.cmd).
	@mkdir -p tests/data/submit_depth_gen; \
	 i=1; while [ $$i -le 64 ]; do \
	   n=$$(printf "%03d" $$i); m=$$(printf "%03d" $$((i+1))); \
	   printf 'SUBMIT "tests/data/submit_depth_gen/c%s.cmd"\n' "$$m" > "tests/data/submit_depth_gen/c$$n.cmd"; \
	   i=$$((i+1)); \
	 done; \
	 printf -- '-- depth-chain terminal (reached only without the guard)\n' > tests/data/submit_depth_gen/c065.cmd
	@failures=0; failed_list=""; total=0; \
	for f in tests/*.cmd; do \
		total=$$((total+1)); \
		base=$$(basename $$f .cmd); \
		exp="tests/expected/$$base.out"; \
		flags="tests/$$base.flags"; \
		extra_flags=""; \
		if [ -f "$$flags" ]; then extra_flags=$$(cat "$$flags"); fi; \
		printf "Testing $$f... "; \
		exitcode_file="tests/$$base.exitcode"; \
		expected_exit=0; \
		if [ -f "$$exitcode_file" ]; then expected_exit=$$(cat "$$exitcode_file"); fi; \
		$(TIMEOUT) 10 ./bin/sdata $$extra_flags $$f > tests/$$base.tmp 2>&1; \
		actual_exit=$$?; \
		if [ $$actual_exit -eq 124 ]; then \
			echo "FAILED (Timed out after 10s)"; \
			rm -f tests/$$base.tmp; \
			failures=$$((failures+1)); failed_list="$$failed_list $$f"; \
		elif [ $$actual_exit -ne $$expected_exit ]; then \
			echo "FAILED (exit $$actual_exit, expected $$expected_exit)"; \
			rm -f tests/$$base.tmp; \
			failures=$$((failures+1)); failed_list="$$failed_list $$f"; \
		elif [ ! -f "$$exp" ]; then \
			echo "FAILED (no expected output file)"; \
			rm -f tests/$$base.tmp; \
			failures=$$((failures+1)); failed_list="$$failed_list $$f"; \
		else \
			diff -wu "$$exp" tests/$$base.tmp > tests/$$base.diff; \
			if [ $$? -eq 0 ]; then \
				echo "PASSED"; \
				rm -f tests/$$base.tmp tests/$$base.diff; \
			else \
				echo "FAILED (output mismatch)"; \
				cat tests/$$base.diff; \
				rm -f tests/$$base.tmp tests/$$base.diff; \
				failures=$$((failures+1)); failed_list="$$failed_list $$f"; \
			fi; \
		fi; \
	done; \
	echo ""; \
	if [ $$failures -gt 0 ]; then \
		echo "$$failures/$$total tests FAILED:"; \
		for t in $$failed_list; do echo "  $$t"; done; \
		exit 1; \
	else \
		echo "All $$total tests passed."; \
	fi

gnatcheck: build
	gnatcheck -P $(GPR_FILE) --rules-file=gnatcheck.rules -j0

complexity-check:
	@GNATMETRIC=$$(scripts/provision-gnatmetric.sh) scripts/check-complexity.sh

fuzz-corpus: build
	@echo "Running corpus regression (csv_fuzz_driver)..."
	@failed=0; \
	for f in tests/fuzz_corpus/csv/*; do \
		[ -f "$$f" ] || continue; \
		printf "  %-52s" "$$f"; \
		if $(TIMEOUT) 5 ./bin/csv_fuzz_driver < "$$f" >/dev/null 2>&1; then \
			echo "OK"; \
		else \
			echo "CRASH (exit $$?)"; failed=$$((failed+1)); \
		fi; \
	done; \
	echo "Running corpus regression (parser_fuzz_driver)..."; \
	for f in tests/fuzz_corpus/script/*; do \
		[ -f "$$f" ] || continue; \
		printf "  %-52s" "$$f"; \
		if $(TIMEOUT) 5 ./bin/parser_fuzz_driver < "$$f" >/dev/null 2>&1; then \
			echo "OK"; \
		else \
			echo "CRASH (exit $$?)"; failed=$$((failed+1)); \
		fi; \
	done; \
	echo "Running corpus regression (ods_fuzz_driver)..."; \
	for f in tests/fuzz_corpus/ods/*; do \
		[ -f "$$f" ] || continue; \
		printf "  %-52s" "$$f"; \
		if $(TIMEOUT) 5 ./bin/ods_fuzz_driver "$$f" >/dev/null 2>&1; then \
			echo "OK"; \
		else \
			echo "CRASH (exit $$?)"; failed=$$((failed+1)); \
		fi; \
	done; \
	echo "Running corpus regression (xlsx_fuzz_driver)..."; \
	for f in tests/fuzz_corpus/xlsx/*; do \
		[ -f "$$f" ] || continue; \
		printf "  %-52s" "$$f"; \
		if $(TIMEOUT) 5 ./bin/xlsx_fuzz_driver "$$f" >/dev/null 2>&1; then \
			echo "OK"; \
		else \
			echo "CRASH (exit $$?)"; failed=$$((failed+1)); \
		fi; \
	done; \
	echo "Running corpus regression (merge_fuzz_driver)..."; \
	for f in tests/fuzz_corpus/merge/*; do \
		[ -f "$$f" ] || continue; \
		printf "  %-52s" "$$f"; \
		if $(TIMEOUT) 5 ./bin/merge_fuzz_driver < "$$f" >/dev/null 2>&1; then \
			echo "OK"; \
		else \
			echo "CRASH (exit $$?)"; failed=$$((failed+1)); \
		fi; \
	done; \
	if [ $$failed -gt 0 ]; then \
		echo "$$failed corpus file(s) caused unexpected crashes."; \
		exit 1; \
	fi; \
	echo "Corpus regression: all OK"

# Build a self-contained sdata-core source tarball for inclusion in the
# srpm / dsc / slackware packages.  Uses 'git archive' on the sibling
# sdata-core checkout, then injects a minimal config/sdata_core_config.gpr
# stub so the tarball builds without Alire (which normally generates
# config/ on first 'alr build').  Output: sdata-core-$(SDATA_CORE_VERSION).tar.gz
# in the current directory.
sdata-core-tarball:
	@if [ ! -d "$(SDATA_CORE_REPO)" ]; then \
	    echo "ERROR: sdata-core not found at $(SDATA_CORE_REPO)"; \
	    echo "  Clone the sibling repo first: git clone <url> $(SDATA_CORE_REPO)"; \
	    exit 1; \
	  fi
	@if [ -n "$$(cd "$(SDATA_CORE_REPO)" && git status --untracked-files=no --porcelain)" ]; then \
	    echo "ERROR: sdata-core working tree not clean ($(SDATA_CORE_REPO))."; \
	    echo "  Commit changes before packaging."; \
	    exit 1; \
	  fi
	@TEMP=$$(mktemp -d); \
	 BASE="sdata-core-$(SDATA_CORE_VERSION)"; \
	 mkdir "$$TEMP/$$BASE"; \
	 (cd "$(SDATA_CORE_REPO)" && git archive --format=tar HEAD) | \
	   tar -x -C "$$TEMP/$$BASE/"; \
	 mkdir -p "$$TEMP/$$BASE/config"; \
	 { \
	   echo '--  Use mathpaqs.gpr (the standalone variant that bundles its own'; \
	   echo '--  APDF copy in graph_pdf/) rather than mathpaqs_project_tree.gpr'; \
	   echo '--  which would import a separate apdf project we do not bundle.'; \
	   echo 'with "mathpaqs.gpr";'; \
	   echo ''; \
	   echo 'abstract project Sdata_Core_Config is'; \
	   echo '   Build_Profile        := "release";'; \
	   echo '   Ada_Compiler_Switches := ();'; \
	   echo 'end Sdata_Core_Config;'; \
	 } > "$$TEMP/$$BASE/config/sdata_core_config.gpr"; \
	 (cd "$$TEMP" && tar czf "sdata-core-$(SDATA_CORE_VERSION).tar.gz" "$$BASE"); \
	 mv "$$TEMP/sdata-core-$(SDATA_CORE_VERSION).tar.gz" .; \
	 rm -rf "$$TEMP"
	@echo "sdata-core tarball created: sdata-core-$(SDATA_CORE_VERSION).tar.gz"

srpm: clean
	@echo "Creating source tarball..."
	@{ \
		if [ -z "$$(git status --untracked-files=no --porcelain)" ]; then \
			git archive --format=tar --prefix=sdata-$(VERSION)/ HEAD | gzip > sdata-$(VERSION).tar.gz; \
		else \
			echo "ERROR: Working directory is not clean. Please commit changes before creating a source package."; \
			exit 1; \
		fi \
	}
	@echo "Building SRPM..."
	@mkdir -p rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
	@mv sdata-$(VERSION).tar.gz rpmbuild/SOURCES/
	@cp sdata.spec rpmbuild/SPECS/
	@# Inject the live sdata-core version so the spec's Source5 / build dir
	@# always match the bundled tarball, regardless of the committed %global.
	@sed -i 's/^%global sdata_core_version .*/%global sdata_core_version $(SDATA_CORE_VERSION)/' rpmbuild/SPECS/sdata.spec
	@# Copy vendored Ada library tarballs from their canonical location.
	@TARBALL_DIR="$(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../Data/tarballs)"; \
	 for tb in zipada-$(ZIPADA_VERSION).tar.gz xmlada-$(XMLADA_VERSION).tar.gz mathpaqs-$(MATHPAQS_VERSION).tar.gz $(SQLITE3_TARBALL).tar.gz $(SQLITE3_TARBALL).tar.gz; do \
	   if [ ! -f "$$TARBALL_DIR/$$tb" ]; then \
	     echo "ERROR: dependency tarball not found: $$TARBALL_DIR/$$tb"; exit 1; \
	   fi; \
	   cp "$$TARBALL_DIR/$$tb" rpmbuild/SOURCES/; \
	 done
	@# Bundle sdata-core (path-pin sibling) as a regular source tarball.
	@$(MAKE) --no-print-directory sdata-core-tarball
	@mv sdata-core-$(SDATA_CORE_VERSION).tar.gz rpmbuild/SOURCES/
	@rpmbuild -bs rpmbuild/SPECS/sdata.spec --define "_topdir $(CURDIR)/rpmbuild"
	@mv rpmbuild/SRPMS/sdata-$(VERSION)-1.src.rpm .
	@rm -rf rpmbuild
	@echo "SRPM created: sdata-$(VERSION)-1.src.rpm"

dsc: clean
	@echo "Creating Debian Source Package..."
	@TARBALL_DIR="$(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../Data/tarballs)"; \
	 CUR_DIR=$$(pwd); \
	 TEMP_DIR=$$(mktemp -d); \
	 BASE_DIR="sdata-$(VERSION)"; \
	 SRC_DIR="$$TEMP_DIR/$$BASE_DIR"; \
	 mkdir -p "$$SRC_DIR"; \
	 git archive --format=tar HEAD | tar -x -C "$$SRC_DIR/"; \
	 for tb in zipada-$(ZIPADA_VERSION).tar.gz xmlada-$(XMLADA_VERSION).tar.gz mathpaqs-$(MATHPAQS_VERSION).tar.gz $(SQLITE3_TARBALL).tar.gz; do \
	   tar xzf "$$TARBALL_DIR/$$tb" -C "$$SRC_DIR/"; \
	 done; \
	 $(MAKE) --no-print-directory sdata-core-tarball >/dev/null; \
	 tar xzf "$$CUR_DIR/sdata-core-$(SDATA_CORE_VERSION).tar.gz" -C "$$SRC_DIR/"; \
	 rm -f "$$CUR_DIR/sdata-core-$(SDATA_CORE_VERSION).tar.gz"; \
	 cd "$$TEMP_DIR" && tar czf "sdata_$(VERSION).orig.tar.gz" "$$BASE_DIR"; \
	 cd "$$SRC_DIR" && dpkg-source -b .; \
	 mv "$$TEMP_DIR"/sdata_$(VERSION)* "$$CUR_DIR/" ; \
	 rm -rf "$$TEMP_DIR"
	@echo "Debian Source Package created (sdata_$(VERSION)-1.dsc, sdata_$(VERSION).orig.tar.gz, etc.)"

slackware: clean
	@echo "Creating SlackBuild tarball..."
	@{ \
		if [ -z "$$(git status --untracked-files=no --porcelain)" ]; then \
			git archive --format=tar --prefix=sdata-$(VERSION)/ HEAD | gzip > sdata-$(VERSION).tar.gz; \
		else \
			echo "ERROR: Working directory is not clean. Please commit changes before creating a source package."; \
			exit 1; \
		fi \
	}
	@TARBALL_DIR="$(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../Data/tarballs)"; \
	 CUR_DIR=$$(pwd); \
	 TEMP_DIR=$$(mktemp -d); \
	 cp sdata-$(VERSION).tar.gz "$$TEMP_DIR/"; \
	 cp slackware/* "$$TEMP_DIR/"; \
	 chmod +x "$$TEMP_DIR/sdata.SlackBuild"; \
	 sed -i 's#sdata-core-[0-9][0-9.]*\.tar\.gz#sdata-core-$(SDATA_CORE_VERSION).tar.gz#' "$$TEMP_DIR/sdata.SlackBuild"; \
	 sed -i 's#^SDATA_CORE_DIR=.*#SDATA_CORE_DIR="sdata-core-$(SDATA_CORE_VERSION)"#' "$$TEMP_DIR/sdata.SlackBuild"; \
	 for tb in zipada-$(ZIPADA_VERSION).tar.gz xmlada-$(XMLADA_VERSION).tar.gz mathpaqs-$(MATHPAQS_VERSION).tar.gz $(SQLITE3_TARBALL).tar.gz; do \
	   cp "$$TARBALL_DIR/$$tb" "$$TEMP_DIR/"; \
	 done; \
	 $(MAKE) --no-print-directory sdata-core-tarball >/dev/null; \
	 mv "sdata-core-$(SDATA_CORE_VERSION).tar.gz" "$$TEMP_DIR/"; \
	 cd "$$TEMP_DIR" && tar czf sdata-$(VERSION)-slackbuild.tar.gz *; \
	 mv "$$TEMP_DIR/sdata-$(VERSION)-slackbuild.tar.gz" "$$CUR_DIR/"; \
	 rm -rf "$$TEMP_DIR"
	@echo "SlackBuild package created: sdata-$(VERSION)-slackbuild.tar.gz"


pkg: build
	@echo "Creating macOS installer package..."
	@TEMP_DIR=$$(mktemp -d); \
	 PKG_ROOT="$$TEMP_DIR/root"; \
	 mkdir -p "$$PKG_ROOT/usr/local/bin"; \
	 mkdir -p "$$PKG_ROOT/usr/local/share/man/man1"; \
	 cp bin/sdata "$$PKG_ROOT/usr/local/bin/sdata"; \
	 chmod 755 "$$PKG_ROOT/usr/local/bin/sdata"; \
	 gzip -9 -c man/man1/sdata.1 > "$$PKG_ROOT/usr/local/share/man/man1/sdata.1.gz"; \
	 chmod 644 "$$PKG_ROOT/usr/local/share/man/man1/sdata.1.gz"; \
	 mkdir -p "$$PKG_ROOT/usr/local/share/doc/sdata"; \
	 install -m 644 README.md "$$PKG_ROOT/usr/local/share/doc/sdata/README.md"; \
	 install -m 644 doc/threat_model.md "$$PKG_ROOT/usr/local/share/doc/sdata/threat_model.md"; \
	 install -m 644 LICENSE "$$PKG_ROOT/usr/local/share/doc/sdata/LICENSE"; \
	 pkgbuild \
	   --root "$$PKG_ROOT" \
	   --identifier com.sdata.pkg \
	   --version $(VERSION) \
	   --install-location / \
	   sdata-$(VERSION).pkg; \
	 rm -rf "$$TEMP_DIR"
	@echo "macOS package created: sdata-$(VERSION).pkg"

install:
	@test -x bin/sdata || { echo "Error: bin/sdata not found. Run 'make' first."; exit 1; }
	install -d $(INSTALL_DIR)
	install -m 755 bin/sdata $(INSTALL_DIR)/sdata
	install -d $(MAN1_DIR)
	install -m 644 man/man1/sdata.1 $(MAN1_DIR)/sdata.1
	gzip -9 -f $(MAN1_DIR)/sdata.1
	install -d $(DOC_DIR)
	install -m 644 README.md $(DOC_DIR)/README.md
	install -m 644 doc/threat_model.md $(DOC_DIR)/threat_model.md
	install -m 644 LICENSE $(DOC_DIR)/LICENSE

# Convert the Unix man page to a self-contained HTML file, used by
# the Windows installer in place of the man page.
sdata.html: man/man1/sdata.1
	@command -v pandoc >/dev/null 2>&1 || { echo "Error: pandoc not found"; exit 1; }
	pandoc -s -f man -t html $< -o $@

# Build a Windows MSI installer using the WiX Toolset (v4 or later;
# v7 recommended). Requires: bin/sdata.exe (run 'make' under MinGW/MSYS
# first), the 'wix' .NET tool, and pandoc on PATH. Install WiX with:
#   dotnet tool install --global wix
# Produces sdata-$(VERSION)-x64.msi.
msi: build sdata.html
	@command -v wix >/dev/null 2>&1 || { echo "Error: wix not found (install with: dotnet tool install --global wix)"; exit 1; }
	@test -x bin/sdata.exe || { echo "Error: bin/sdata.exe not found. Build under Windows first."; exit 1; }
	@echo "Building MSI installer..."
	wix build -arch x64 -d Version=$(VERSION) -out sdata-$(VERSION)-x64.msi wix/sdata.wxs
	@echo "MSI created: sdata-$(VERSION)-x64.msi"

clean:
	@echo "Cleaning build artifacts..."
	rm -rf obj bin tests/*.tmp tests/*.diff sdata_opt_tab.csv sdata_opt_nohdr.csv \
	       sdata.html wix/*.wixobj *.wixpdb sdata-*-x64.msi
