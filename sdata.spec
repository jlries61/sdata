Name:           sdata
Version:        0.14.0
Release:        1%{?dist}
Summary:        A statistical data interpreter for processing datasets.

# Bundled sdata-core version (path-pin sibling during development).
# Fallback only: `make srpm` overwrites this in rpmbuild/SPECS/sdata.spec with
# the value derived from ../sdata-core/alire.toml, so it cannot drift for a
# packaged build. Kept current here so a direct build from the committed spec
# still resolves Source5.
%global sdata_core_version 0.1.26

License:        GPLv3
URL:            https://github.com/jlries61/sdata
Source0:        %{name}-%{version}.tar.gz
Source1:        zipada-61.0.0.tar.gz
Source2:        xmlada-26.0.0.tar.gz
Source3:        mathpaqs-20260205.0.0.tar.gz
Source4:        ada_sqlite3_0.1.1_2edbcebd.tar.gz
Source5:        sdata-core-%{sdata_core_version}.tar.gz

# GNAT (Ada compiler) package name differs across RPM distributions:
#   gcc-ada   — openSUSE, SLES
#   gcc-gnat  — Fedora, RHEL/CentOS Stream/Rocky/Alma, Mageia, OpenMandriva
# The boolean OR syntax requires RPM >= 4.13 (Fedora 27+, openSUSE Leap 15.1+,
# RHEL 8+).  If building on an older release substitute the appropriate name.
BuildRequires:  (gcc-ada or gcc-gnat)
BuildRequires:  make
BuildRequires:  sqlite-devel

%description
sdata is a statistical data interpreter designed for data step-based
processing. It includes a comprehensive suite of statistical distributions,
aggregate functions, and advanced variable handling.

%prep
%setup -q
# Extract vendored Ada library dependencies alongside the main source.
tar xzf %{SOURCE1} -C %{_builddir}
tar xzf %{SOURCE2} -C %{_builddir}
tar xzf %{SOURCE3} -C %{_builddir}
tar xzf %{SOURCE4} -C %{_builddir}
# sdata-core is path-pinned in alire.toml; bundled here as a regular tarball
# since 'alr build' is not used in the RPM environment.
tar xzf %{SOURCE5} -C %{_builddir}

# Suppress strict style checks and warnings in the ada_sqlite3 dependency to reduce build log noise.
sed -i 's/"-gnaty.*"/"-gnatws"/g' %{_builddir}/ada_sqlite3_0.1.1_2edbcebd/config/ada_sqlite3_config.gpr
sed -i 's/"-gnatwa"/"-gnatws"/g' %{_builddir}/ada_sqlite3_0.1.1_2edbcebd/config/ada_sqlite3_config.gpr

%build
# Point gprbuild at the vendored dependency .gpr files.
# xmlada keeps dom and input_sources in separate subdirectories.
# sdata-core's .gpr lives at the root of its unpacked tarball.
export GPR_PROJECT_PATH="%{_builddir}/zipada_61.0.0_54fc9836:%{_builddir}/xmlada_26.0.0_b140ed4a/dom:%{_builddir}/xmlada_26.0.0_b140ed4a/input_sources:%{_builddir}/mathpaqs_20260205.0.0_abed7ef9:%{_builddir}/ada_sqlite3_0.1.1_2edbcebd:%{_builddir}/sdata-core-%{sdata_core_version}"
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
# Override DOCDIR so it matches RPM's %{_docdir} convention (which differs
# between distros: /usr/share/doc on Fedora/RHEL, /usr/share/doc/packages
# on openSUSE).
make install DESTDIR=%{buildroot} PREFIX=/usr DOCDIR=%{_docdir}/%{name}

%files
%license LICENSE
%{_bindir}/sdata
%{_mandir}/man1/sdata.1*
%{_docdir}/%{name}/README.md
%{_docdir}/%{name}/threat_model.md
%{_docdir}/%{name}/LICENSE

%changelog
* Sat Jul 11 2026 John L. Ries <john@theyarnbard.com> - 0.14.0-1
- SAVE /DECIMALS=N option and round-trip float output in CSV/ODF/OOXML writers

* Wed Jul 08 2026 John L. Ries <john@theyarnbard.com> - 0.13.3-1
- Complete audit remediation #3: Render_List enumerates observed tuples instead of the full Cartesian product of level cardinalities (O(rows) not O(product), byte-identical output).

* Wed Jul 08 2026 John L. Ries <john@theyarnbard.com> - 0.13.2-1
- Audit remediations #3 (TABLES/STATS efficiency: O(1) hashed level lookups, STATS per-statistic re-copy hoist) and #4 (actionable $/%-in-SELECT diagnostic, issue #73). Requires sdata-core 0.1.26.

* Tue Jul 07 2026 John L. Ries <john@theyarnbard.com> - 0.13.1-1
- Milestone refactor: TABLES consumes sdata-core Group_Boundaries (R3)

* Fri Jul 03 2026 John L. Ries <john@theyarnbard.com> - 0.13.0-1
- Add TABLES command (PROC FREQ analogue): one-way, two-way, and multiway frequency/crosstabulation reports with optional chi-square-family statistics

* Fri Jul 03 2026 John L. Ries <john@theyarnbard.com> - 0.12.3-1
- Clearer error when a wide dataset exceeds the SQLite disk-spill column limit (A/B for the OUTPUT-adjacent spill report)

* Thu Jul 02 2026 John L. Ries <john@theyarnbard.com> - 0.12.2-1
- Fix OUTPUT redirect file being truncated by a subsequent RUN (issue #40)

* Thu Jul 02 2026 John L. Ries <john@theyarnbard.com> - 0.12.1-1
- Entry-time semantic checking of deferred statements (type-mismatch, unknown-function, arity, undefined-variable); USE/REPEAT cancel the deferred program

* Wed Jul 01 2026 John L. Ries <john@theyarnbard.com> - 0.12.0-1
- Add STATS command (PROC MEANS analogue)

* Fri Jun 26 2026 John L. Ries <john@theyarnbard.com> - 0.11.1-1
- INSERT command for interactive program-buffer editing (issue #32).

* Fri Jun 26 2026 John L. Ries <john@theyarnbard.com> - 0.11.0-1
- TRANSPOSE command — reshape table columns to rows

* Wed Jun 24 2026 John L. Ries <john@theyarnbard.com> - 0.10.1-1
- Fix NEW crash after a failed RUN; detect literal LET/SET type conflicts at entry (#31).

* Tue Jun 23 2026 John L. Ries <john@theyarnbard.com> - 0.10.0-1
- AGGREGATE command

* Sat Jun 20 2026 John L. Ries <john@theyarnbard.com> - 0.9.8-1
- Backtick-quoted identifiers; USE-time reserved-keyword warning; OPTIONS WARNRESERVED command

* Tue Jun 09 2026 John L. Ries <john@theyarnbard.com> - 0.9.7-1
- Performance: fix three O(n^2) hotspots in the data step (Get_Column_Type whole-column copy, transient-table copy-per-cell, BY re-sort per record) -- large data-step scripts ~70x faster

* Sat Jun 06 2026 John L. Ries <john@theyarnbard.com> - 0.9.6-1
- USE/SAVE RENAME= applies suffix-determines-type: float<->integer convert (truncating toward zero), numeric<->character rejected; single-dataset USE and single-target SAVE now honor rename/keep/drop options

* Fri Jun 05 2026 John L. Ries <john@theyarnbard.com> - 0.9.5-1
- Load %-suffixed header columns as integer (sdata-core 0.1.5).

* Wed Jun 03 2026 John L. Ries <john@theyarnbard.com> - 0.9.4-1
- Add USE /APPEND merge mode for vertical concatenation of datasets

* Mon Jun 01 2026 John L. Ries <john@theyarnbard.com> - 0.9.3-1
- Migrate sdata_unit_test.adb's direct Runtime field writes to Execute_OPTIONS helper (precondition for sdata-core Runtime privatization).

* Mon Jun 01 2026 John L. Ries <john@theyarnbard.com> - 0.9.2-1
- Phase B of audit item #5 — migrate direct Runtime field writes to End_Repeat / Clear_Pending_Save helpers (precondition for Phase C privatization).

* Mon Jun 01 2026 John L. Ries <john@theyarnbard.com> - 0.9.1-1
- USE alias uniqueness, IN= read-only enforcement, build-warning cleanup, missing error tests, architecture doc refresh

* Mon Jun 01 2026 John L. Ries <john@theyarnbard.com> - 0.9.0-1
- Multi-dataset USE merge (4 modes), multi-target SAVE with per-record IF= routing, per-row IN= provenance, OPTIONS JOIN_WARN_THRESHOLD

* Tue May 26 2026 John L. Ries <john@theyarnbard.com> - 0.8.1-1
- Packaging fixes for sdata-core split (RPM, Debian, Slackware); AST Options_Key_Len/Val_Len initialization fix.

* Thu May 21 2026 John L. Ries <john@theyarnbard.com> - 0.8.0-1
- Extract VANDALIZE into standalone data-vandal application; introduce sdata-core shared library.

* Mon May 18 2026 John L. Ries <john@theyarnbard.com> - 0.7.1-1
- feat: VANDALIZE supports virtual arrays (ARRAY command) as source

* Fri May 15 2026 John L. Ries <john@theyarnbard.com> - 0.7.0-1
- Add VANDALIZE command for synthetic data generation, anonymisation, and sensitivity testing

* Thu May 14 2026 John L. Ries <john@theyarnbard.com> - 0.6.14-1
- configurable --debug log levels (--debug=N, OPTIONS DEBUG N)

* Wed May 13 2026 John L. Ries <john@theyarnbard.com> - 0.6.13-1
- Decompose interpreter monolith into 9 Ada subunits; add shell timeout (ADR-037)

* Tue May 12 2026 John L. Ries <john@theyarnbard.com> - 0.6.12-1
- refactor: decompose sdata-file_io.adb into child packages; fix broad when-others handlers; add Execute_Assignment unit tests (IC-35..IC-41)

* Fri May 08 2026 John L. Ries <john@theyarnbard.com> - 0.6.11-1
- Refactor Parse_ODF/Parse_OOXML; remove version from HELP output

* Thu May 07 2026 John L. Ries <john@theyarnbard.com> - 0.6.10-1
- Expand unit tests (csv_unit_test 71 tests, sdata_unit_test 98 tests); fix NRN() normal distribution bug; add SYSTEM as immediate command; annotate standards review.

* Wed May 06 2026 John L. Ries <john@theyarnbard.com> - 0.6.9-1
- Add Inf/-Inf support: first-class IEEE 754 infinity, INF() function, OPTIONS IEEE_DIVIDE, NaN detection, full CSV/ODF/OOXML round-trip.

* Tue May 05 2026 John L. Ries <john@theyarnbard.com> - 0.6.8-1
- Refactor evaluator into child packages; add HELP CONCEPTS; correct SET variable description.

* Sat May 02 2026 John L. Ries <john@theyarnbard.com> - 0.6.7-1
- HELP coverage (8 tests); CI binary guard; DIM resize fix + expand/shift tests (110 total)

* Fri May 01 2026 John L. Ries <john@theyarnbard.com> - 0.6.6-1
- Debug system: passive trace, BREAK/BREAK WHEN statement, inspection REPL
- Fix SELECT CASE parsing in interactive REPL (Incomplete_Statement on EOF)

* Thu Apr 30 2026 John L. Ries <john@theyarnbard.com> - 0.6.5-1
- Software standards review and Pi verification audit (Stages 1-5)

* Wed Apr 29 2026 John L. Ries <john@theyarnbard.com> - 0.6.4-1
- Array slice/list assignment; range subscripts in aggregate functions and PRINT; LET/SET array element restrictions; NEW clears virtual arrays

* Tue Apr 28 2026 John L. Ries <john@theyarnbard.com> - 0.6.3-1
- Bump to 0.6.3: SKIP/MAXROWS for USE; ZCF/ZDF/ZIF/ZRN optional mu/sigma;
  URN/ZRN zero-arg defaults; undefined variable errors; expand no-paren
  function whitelist; multi-char delimiters; CHARSET encoding for CSV

* Mon Apr 27 2026 John L. Ries <john@theyarnbard.com> - 0.6.2-1
- Bump to 0.6.2

* Fri Apr 24 2026 John L. Ries <john@theyarnbard.com> - 0.6.1-1
- Fix 101x spillover penalty: segment-level prefetch and Constant_Reference spill.

* Tue Apr 21 2026 John L. Ries <john@theyarnbard.com> - 0.6.0-1
- Add DISPLAY command, LIST program-buffer display, DELETE n[-m] program-buffer deletion, ERR/ERL functions

* Fri Apr 17 2026 John L. Ries <john@theyarnbard.com> - 0.5.2-1
- Register SIGTERM/SIGINT handlers for temp-file cleanup; extract SData.Config.Runtime; complete dispatch table; break evaluator-interpreter cycle.

* Wed Apr 15 2026 John L. Ries <john@theyarnbard.com> - 0.5.1-1
- Fix storage engine stability and data ordering; improve internal pager newline handling.

* Wed Apr 15 2026 John L. Ries <john@theyarnbard.com> - 0.5.0-1
- Complete Phase 5: Implement Memory-to-Disk Spillover, SQLite-backed sorting, and performance optimizations.

* Wed Apr 15 2026 John L. Ries <john@theyarnbard.com> - 0.4.2-1
- Address SKEPTIC review findings; refactor Config and Evaluator; complete distribution RNs.

* Wed Apr 15 2026 John L. Ries <john@theyarnbard.com> - 0.4.1-1
- Finalize Phase 3 and Phase 4 development.
- Implement LIST command for data display.
- Finalize statistical distributions: add MIF (Binomial IDF) and BRN (Beta RN).
- Enhance SELECT record filter: make non-cumulative and add /ALL to cancel.
- Implement merged cell detection for ODF and OOXML (fails with error).
- Implement ORD() function as synonym for logical record number.
- Document -p pager/noshell incompatibility and batch-mode behavior.

* Fri Apr 10 2026 John L. Ries <john@theyarnbard.com> - 0.4.0-1
- Add multi-sheet ODF/OOXML support (/SHEET= flag); formula detection with LibreOffice subprocess fallback.

* Fri Apr 10 2026 John L. Ries <john@theyarnbard.com> - 0.3.4-1
- Harden sdata_main.adb: unbounded REPL input, numeric arg error handling, bounds checks; add bump-version.sh script; fix Is_Immediate gaps; add AST memory management; narrow exception handlers in evaluator.

* Fri Apr 10 2026 John L. Ries <john@theyarnbard.com> - 0.3.3-1
- Add GPL-3.0 license file; update license declarations throughout.
- Fix Makefile: remove hardcoded Alire path; centralize VERSION and tarball version variables.
- Harden sdata_main.adb: safe Read_File, bounds checks on command-line path arguments.
- Extract Is_Immediate predicate into SData.Interpreter; fix missing ECHO/SORT/BY/SELECT_FILTER.
- Add AST memory management: Free_Program recursively frees all AST node types.
- Narrow broad 'when others' exception handlers in sdata-evaluator.adb to Constraint_Error.
- Sync alire.toml dependency versions with installed libraries.

* Wed Apr 08 2026 John L. Ries <john@theyarnbard.com> - 0.3.2-1
- Fix ODF/OOXML import: infer column types from first data row; warn on skipped cells.
- Refactor Execute_Statement into named handler procedures; promote Run_One_Step.
- Add --debug flag to trace statement execution and record numbers to stderr.
- Set POSIX exit status on script errors; add .exitcode support to test harness.
- Add doc/architecture.md describing the three-tier execution model.

* Tue Apr 07 2026 John L. Ries <john@theyarnbard.com> - 0.3.1-1
- Code quality: refactor Print_Help into data-driven SData.Help package;
  eliminates 685-line if/elsif chain and ~18 unreachable duplicate entries.
- Bug fix: table row limit now raises Script_Error instead of Program_Error.
- Bug fix: narrow OOXML cell parse exception handler to Constraint_Error.
- Add CI workflow (.github/workflows/test.yml) to run make check on push/PR.
- Repo cleanup: remove stale root-level data files; move test data to tests/data/.

* Mon Apr 06 2026 John L. Ries <john@theyarnbard.com> - 0.3.0-1
- Phase 3 complete: SELECT row filter, BY-group processing, filter-aware
  LAG/NEXT/RECNO/BOF/EOF, SELECT /ALL, bare BY to cancel grouping, NEW
  resets both filter and grouping.
- Add manpage (man/man1/sdata.1).
- Expand HELP text for aggregate and statistical functions.
- Add explanatory comments to interpreter, evaluator, and parser.

* Mon Mar 30 2026 John L. Ries <john@theyarnbard.com> - 0.2.2-1
- Performance optimizations for SORT and data steps.
- Replaced bubble sort with heapsort (O(n log n)).
- Optimized Value type using Unbounded_String to reduce memory footprint.
- Optimized table access using Ada 2012 Reference types.
- Fixed FPATH not executing in REPL.
- Fixed several CSV parsing and header preservation bugs.

* Mon Mar 23 2026 John L. Ries <john@theyarnbard.com> - 0.2.0-1
- Phase 2 complete: Robust control flow and standardized function library.

* Mon Mar 23 2026 John L. Ries <john@theyarnbard.com> - 0.1.1-1
- Finalize Phase 1 with corrected memory architecture and parser.

* Tue Mar 17 2026 John L. Ries <john@theyarnbard.com> - 0.1-1
- Bundle Ada library dependencies (zipada, xmlada, mathpaqs)
  as vendored sources so the build requires only gcc-gnat/gcc-ada and
  make with no additional Ada library packages.
- Use (gcc-ada or gcc-gnat) boolean dependency to support both
  openSUSE/SLES and Fedora/RHEL naming conventions.
- Remove explicit gprbuild dependency to allow builds using Alire-managed
  toolchains in the user's path.
