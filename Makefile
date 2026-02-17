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
	./bin/sdata_main tests/test1.sdata

check: build
	@echo "Running tests..."
	@for f in tests/*.sdata; do \
		echo "Testing $$f..."; \
		./bin/sdata_main $$f > /tmp/test_out; \
		if [ $$? -eq 0 ]; then \
			echo "  $$f: PASSED"; \
		else \
			echo "  $$f: FAILED"; \
			exit 1; \
		fi \
	done
	@echo "All tests passed."

clean:
	rm -rf obj bin
