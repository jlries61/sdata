Name:           sdata
Version:        0.1
Release:        1%{?dist}
Summary:        A statistical data interpreter for processing datasets.

License:        MIT
URL:            https://github.com/user/sdata
Source0:        %{name}-%{version}.tar.gz

# GNAT (Ada compiler) package name differs across RPM distributions:
#   gcc-ada   — openSUSE, SLES
#   gcc-gnat  — Fedora, RHEL/CentOS/Rocky/Alma, Mageia, OpenMandriva
# The boolean OR syntax requires RPM >= 4.13 (Fedora 27+, openSUSE Leap 15.1+,
# RHEL 8+).  If building on an older release substitute the appropriate name.
BuildRequires:  (gcc-ada or gcc-gnat)
BuildRequires:  gprbuild
BuildRequires:  make

%description
sdata is a statistical data interpreter designed for data step-based
processing. It includes a comprehensive suite of statistical distributions,
aggregate functions, and advanced variable handling.

%prep
%setup -q

%build
# The Makefile prefers the Alire-managed gprbuild if present and falls back
# to the system gprbuild (installed via the gprbuild BuildRequires above).
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
make install DESTDIR=%{buildroot} PREFIX=/usr

%files
%{_bindir}/sdata

%changelog
* Wed Mar 04 2026 Your Name <you@example.com> - 0.1-1
- Initial RPM packaging.
