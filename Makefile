# Makefile for SData

GNATMAKE = gnatmake
GPRBUILD = gprbuild
GPR_FILE = sdata.gpr

.PHONY: all build clean run check

all: build

build:
	@if command -v $(GPRBUILD) >/dev/null 2>&1; then \
		$(GPRBUILD) -P $(GPR_FILE); \
	else \
		mkdir -p obj bin; \
		$(GNATMAKE) -gnat2012 -Isrc -Isrc/lexer -Isrc/parser -Isrc/ast src/sdata_main.adb -D obj -o bin/sdata_main; \
	fi

run: build
	./bin/sdata_main tests/test1.cmd

check: build
	@echo "Running tests..."
	@for f in tests/*.cmd; do \
		base=$$(basename $$f .cmd); \
		exp="tests/expected/$$base.out"; \
		echo -n "Testing $$f... "; \
		./bin/sdata_main $$f > tests/$$base.tmp 2>&1; \
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

clean:
	rm -rf obj bin tests/*.tmp tests/*.diff
