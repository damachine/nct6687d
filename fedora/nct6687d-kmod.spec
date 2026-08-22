%if 0%{?fedora}
%global buildforkernels akmod
%endif
%global debug_package %{nil}

%global prjname nct6687d
%global pkgver MAKEFILE_PKGVER
%global commithash MAKEFILE_COMMITHASH

Name:           %{prjname}-kmod
Version:        1.0.%{pkgver}
Release:        1.git%{commithash}%{?dist}
Summary:        Kernel module (kmod) for %{prjname}
License:        GPL-2.0-or-later
URL:            https://github.com/Fred78290/nct6687d
Source0:        nct6687d-%{version}.tar.gz

%global AkmodsBuildRequires %{_bindir}/kmodtool, gcc, make, elfutils-libelf-devel
BuildRequires:  %{AkmodsBuildRequires}
%{!?kernels:BuildRequires: buildsys-build-rpmfusion-kerneldevpkgs-%{?buildforkernels:%{buildforkernels}}%{!?buildforkernels:current}-%{_target_cpu} }

%{expand:%(kmodtool --target %{_target_cpu} --repo rpmfusion --kmodname %{prjname} %{?buildforkernels:--%{buildforkernels}} %{?kernels:--for-kernels "%{?kernels}"} 2>/dev/null) }

%description
%{prjname} kernel module

%prep
%{?kmodtool_check}

kmodtool --target %{_target_cpu} --repo rpmfusion --kmodname %{prjname} %{?buildforkernels:--%{buildforkernels}} %{?kernels:--for-kernels "%{?kernels}"} 2>/dev/null

%autosetup -n nct6687d-%{version}

for kernel_version in %{?kernel_versions} ; do
    cp -a nct6687d _kmod_build_${kernel_version%%___*}
done

%build
for kernel_version in %{?kernel_versions}; do
    make V=0 %{?_smp_mflags} -C "${kernel_version##*___}" M=${PWD}/_kmod_build_${kernel_version%%___*}
done

%install
for kernel_version in %{?kernel_versions}; do
 mkdir -p %{buildroot}%{kmodinstdir_prefix}/${kernel_version%%___*}/%{kmodinstdir_postfix}/
 install -D -m 755 _kmod_build_${kernel_version%%___*}/*.ko %{buildroot}%{kmodinstdir_prefix}/${kernel_version%%___*}/%{kmodinstdir_postfix}/
 chmod a+x %{buildroot}%{kmodinstdir_prefix}/${kernel_version%%___*}/%{kmodinstdir_postfix}/*.ko
done
%{?akmod_install}


%changelog
* Wed Jan 04 2023 Frederic BOLTZ <frederic.boltz@gmail.com> - %{version}
- Initial package
