Name:           sdata
Version:        0.1
Release:        1%{?dist}
Summary:        A statistical data interpreter for processing datasets.

License:        MIT
URL:            https://github.com/user/sdata
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc-ada
BuildRequires:  make

%description
sdata is a statistical data interpreter designed for data step-based
processing. It includes a comprehensive suite of statistical distributions,
aggregate functions, and advanced variable handling.

%prep
%setup -q

%build
# The GPRBUILD_ALIRE_PATH is hardcoded in the Makefile for this project
# In a more standard setup, you would rely on the system's gprbuild.
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
%make_install

%files
%{_bindir}/sdata

%changelog
* Wed Mar 04 2026 Your Name <you@example.com> - 0.1-1
- Initial RPM packaging.
