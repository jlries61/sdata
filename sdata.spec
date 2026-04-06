Name:           sdata
Version:        0.3.0
Release:        1%{?dist}
Summary:        A statistical data interpreter for processing datasets.

License:        MIT
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
* Sun Apr 06 2026 John L. Ries <john@theyarnbard.com> - 0.3.0-1
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
