# Makefile for SData

GPR_FILE = sdata.gpr
GPRBUILD_ALIRE_PATH := /home/jries/.local/share/alire/toolchains/gprbuild_25.0.1_9a2e6cfb/bin/gprbuild
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
		echo -n "Testing $$f... "; \
		./bin/sdata $$f > tests/$$base.tmp 2>&1; \
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
	@rpmbuild -bs rpmbuild/SPECS/sdata.spec --define "_topdir %(pwd)/rpmbuild"
	@mv rpmbuild/SRPMS/sdata-0.1-1.suse.src.rpm .
	@rm -rf rpmbuild
	@echo "SRPM created: sdata-0.1-1.suse.src.rpm"


install: build
	install -d $(INSTALL_DIR)
	install -m 755 bin/sdata $(INSTALL_DIR)/sdata

clean:
	@echo "Cleaning build artifacts..."
	rm -rf obj bin tests/*.tmp tests/*.diff
