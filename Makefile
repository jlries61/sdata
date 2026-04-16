# Makefile for SData

VERSION          := 0.5.1
ZIPADA_VERSION   := 61.0.0
XMLADA_VERSION   := 26.0.0
MATHPAQS_VERSION := 20260205.0.0
SQLITE3_TARBALL  := ada_sqlite3_0.1.1_2edbcebd

GPR_FILE = sdata.gpr
# Use GPRBUILD from the environment or command line if set; otherwise detect
# from PATH.  When working with an Alire-managed toolchain, run 'alr build'
# directly, or ensure the toolchain is on PATH via 'eval $(alr printenv)'.
GPRBUILD ?= $(firstword $(shell which gprbuild 2>/dev/null) gprbuild)
# GNU coreutils 'timeout' is 'gtimeout' on macOS/MacPorts; fall back to plain
# 'timeout' (Linux) if 'gtimeout' is not found.
TIMEOUT  := $(firstword $(shell which gtimeout 2>/dev/null) timeout)

# GPR_PROJECT_PATH: tells gprbuild where to find dependency .gpr files.
# If already set in the environment (e.g. by the RPM spec), use that.
# Otherwise auto-detect from the sibling source directories in the parent.
#
# Note: these sibling directories (zipada_*, xmlada_*, mathpaqs_*) are the
# library sources used for 'make build' and for packaging targets (srpm, dsc,
# slackware).  They are separate from the copies that 'alr build' manages in
# ~/.local/share/alire/builds/ -- both paths use the same library versions,
# they are just physically independent.
DEP_BASE := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
_ZIPADA_DIR    := $(firstword $(wildcard $(DEP_BASE)/zipada_*))
_XMLADA_DIR    := $(firstword $(wildcard $(DEP_BASE)/xmlada_*))
_MATHPAQS_DIR  := $(firstword $(wildcard $(DEP_BASE)/mathpaqs_*))
_SQLITE3_DIR   := $(firstword $(wildcard $(DEP_BASE)/ada_sqlite3_*))
_LOCAL_GPR_PATH := $(_ZIPADA_DIR):$(_XMLADA_DIR)/dom:$(_XMLADA_DIR)/input_sources:$(_MATHPAQS_DIR):$(_SQLITE3_DIR)
export GPR_PROJECT_PATH ?= $(_LOCAL_GPR_PATH)
PREFIX ?= /usr/local
BINDIR  = $(PREFIX)/bin
MANDIR  = $(PREFIX)/share/man
INSTALL_DIR  = $(DESTDIR)$(BINDIR)
MAN1_DIR     = $(DESTDIR)$(MANDIR)/man1

.PHONY: all build clean run check install srpm pkg

all: build

build:
	$(GPRBUILD) -P $(GPR_FILE)

run: build
	@if [ -z "$(FILE)" ]; then \
		echo "Error: please specify a script to run with FILE=<path>"; \
		echo "Usage: make run FILE=tests/test1.cmd"; \
		exit 1; \
	fi
	./bin/sdata $(FILE)

check: build
	@echo "Running tests..."
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
			diff -u "$$exp" tests/$$base.tmp > tests/$$base.diff; \
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
	@# Copy vendored Ada library tarballs from their canonical location.
	@TARBALL_DIR="$(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../Data/tarballs)"; \
	 for tb in zipada-$(ZIPADA_VERSION).tar.gz xmlada-$(XMLADA_VERSION).tar.gz mathpaqs-$(MATHPAQS_VERSION).tar.gz $(SQLITE3_TARBALL).tar.gz $(SQLITE3_TARBALL).tar.gz; do \
	   if [ ! -f "$$TARBALL_DIR/$$tb" ]; then \
	     echo "ERROR: dependency tarball not found: $$TARBALL_DIR/$$tb"; exit 1; \
	   fi; \
	   cp "$$TARBALL_DIR/$$tb" rpmbuild/SOURCES/; \
	 done
	@rpmbuild -bs rpmbuild/SPECS/sdata.spec --define "_topdir %(pwd)/rpmbuild"
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
	 for tb in zipada-$(ZIPADA_VERSION).tar.gz xmlada-$(XMLADA_VERSION).tar.gz mathpaqs-$(MATHPAQS_VERSION).tar.gz $(SQLITE3_TARBALL).tar.gz; do \
	   cp "$$TARBALL_DIR/$$tb" "$$TEMP_DIR/"; \
	 done; \
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

clean:
	@echo "Cleaning build artifacts..."
	rm -rf obj bin tests/*.tmp tests/*.diff
