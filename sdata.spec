Name:           sdata
Version:        0.4.0
Release:        1%{?dist}
Summary:        A statistical data interpreter for processing datasets.

License:        GPLv3
URL:            https://github.com/user/sdata
Source0:        %{name}-%{version}.tar.gz
Source1:        zipada-61.0.0.tar.gz
Source2:        xmlada-26.0.0.tar.gz
Source3:        mathpaqs-20260205.0.0.tar.gz

# GNAT (Ada compiler) package name differs across RPM distributions:
#   gcc-ada   — openSUSE, SLES
#   gcc-gnat  — Fedora, RHEL/CentOS Stream/Rocky/Alma, Mageia, OpenMandriva
# The boolean OR syntax requires RPM >= 4.13 (Fedora 27+, openSUSE Leap 15.1+,
# RHEL 8+).  If building on an older release substitute the appropriate name.
BuildRequires:  (gcc-ada or gcc-gnat)
BuildRequires:  make

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

%build
# Point gprbuild at the vendored dependency .gpr files.
# xmlada keeps dom and input_sources in separate subdirectories.
export GPR_PROJECT_PATH="%{_builddir}/zipada_61.0.0_54fc9836:%{_builddir}/xmlada_26.0.0_b140ed4a/dom:%{_builddir}/xmlada_26.0.0_b140ed4a/input_sources:%{_builddir}/mathpaqs_20260205.0.0_abed7ef9"
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
make install DESTDIR=%{buildroot} PREFIX=/usr

%files
%{_bindir}/sdata
%{_mandir}/man1/sdata.1*

%changelog
* Fri Apr 10 2026 John L. Ries <john@theyarnbard.com> - 0.4.0-1
- Add multi-sheet ODF/OOXML support (/SHEET= flag); formula detection with LibreOffice subprocess fallback.

* Fri Apr 10 2026 John L. Ries <john@theyarnbard.com> - 0.3.4-1
- Harden sdata_main.adb: unbounded REPL input, numeric arg error handling, bounds checks; add bump-version.sh script; fix Is_Immediate gaps; add AST memory management; narrow exception handlers in evaluator.

* Thu Apr 10 2026 John L. Ries <john@theyarnbard.com> - 0.3.3-1
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
