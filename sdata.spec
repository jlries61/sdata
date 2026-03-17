Name:           sdata
Version:        0.1
Release:        1%{?dist}
Summary:        A statistical data interpreter for processing datasets.

License:        MIT
URL:            https://github.com/user/sdata
Source0:        %{name}-%{version}.tar.gz
Source1:        zipada-61.0.0.tar.gz
Source2:        xmlada-26.0.0.tar.gz
Source3:        mathpaqs-20260205.0.0.tar.gz
Source4:        sciada-0.4.0.tar.gz

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
tar xzf %{SOURCE4} -C %{_builddir}

%build
# Point gprbuild at the vendored dependency .gpr files.
# xmlada keeps dom and input_sources in separate subdirectories.
export GPR_PROJECT_PATH="%{_builddir}/zipada_61.0.0_54fc9836:%{_builddir}/xmlada_26.0.0_b140ed4a/dom:%{_builddir}/xmlada_26.0.0_b140ed4a/input_sources:%{_builddir}/mathpaqs_20260205.0.0_abed7ef9:%{_builddir}/sciada_0.4.0_af24740d"
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
make install DESTDIR=%{buildroot} PREFIX=/usr

%files
%{_bindir}/sdata

%changelog
* Tue Mar 17 2026 John L. Ries <john@theyarnbard.com> - 0.1-1
- Bundle Ada library dependencies (zipada, xmlada, mathpaqs, sciada)
  as vendored sources so the build requires only gcc-gnat/gcc-ada and
  make with no additional Ada library packages.
- Use (gcc-ada or gcc-gnat) boolean dependency to support both
  openSUSE/SLES and Fedora/RHEL naming conventions.
- Remove explicit gprbuild dependency to allow builds using Alire-managed
  toolchains in the user's path.
