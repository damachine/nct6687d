%global prjname nct6687d
%global pkgver MAKEFILE_PKGVER
%global commithash MAKEFILE_COMMITHASH

Name:           nct6687d
Version:        1.0.%{pkgver}
Release:        1.git%{commithash}%{?dist}
Summary:        Kernel module (kmod) for %{prjname}
License:        GPL-2.0-or-later
URL:            https://github.com/Fred78290/nct6687d
Source0:        nct6687.conf
Source1:        LICENSE

BuildRequires:  systemd-rpm-macros

# For kmod package
Provides:       %{name}-kmod-common = %{version}-%{release}
Requires:       %{name}-kmod >= %{version}

BuildArch:      noarch

%description
%{prjname} kernel module

%prep

%build
# Nothing to build

%install

install -D -m 0644 %{SOURCE0} %{buildroot}%{_modulesloaddir}/nct6687.conf
install -D -m 0644 %{SOURCE1} %{buildroot}%{_licensedir}/%{name}/LICENSE

%files
%license %{_licensedir}/%{name}/LICENSE
%{_modulesloaddir}/nct6687.conf

%changelog
* Wed Jan 04 2023 Frederic BOLTZ <frederic.boltz@gmail.com> - %{version}
- Initial package
