# Vitrine, packaged for Fedora Workstation.
#
# Build it with ../../packaging/fedora/build-rpm.sh, which makes the source
# tarball this spec expects and hands it to rpmbuild.
#
# Two things keep this out of the Fedora repositories as it stands, and both
# are deliberate for a package you build yourself:
#
#   * The build resolves adwaita-swift over the network. Fedora's build system
#     runs offline, so a repository package would have to vendor or bundle it.
#   * There is no LICENSE file in the source tree yet, so there is no licence
#     to declare. Set both License fields once one lands.

%global appid    app.vitrine.Vitrine
%global privdir  %{_libexecdir}/vitrine

# The Swift toolchain's own debug output is not useful here, and stripping the
# binary upsets it; leave both alone.
%global debug_package %{nil}
%global __brp_strip %{nil}

Name:           vitrine
Version:        1.1
Release:        1%{?dist}
Summary:        Blender build manager

License:        LicenseRef-Unspecified
URL:            https://github.com/claxonberlin/Vitrine
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  swift-lang
BuildRequires:  gtk4-devel
BuildRequires:  libadwaita-devel
BuildRequires:  pkgconf-pkg-config
BuildRequires:  desktop-file-utils
BuildRequires:  libappstream-glib

Requires:       gtk4
Requires:       libadwaita
Requires:       tar
Requires:       xz

# Adwaita for Swift has no aarch64 problem of its own, but the Swift toolchain
# Fedora ships is x86_64 and aarch64 only.
ExclusiveArch:  x86_64 aarch64

%description
Vitrine browses the Blender download catalogue, installs the versions you pick,
and keeps them side by side in one library. Star a build to make it your main
Blender: the one the terminal finds, and the one that opens a .blend file.

The GNOME front end is written with Adwaita for Swift over a core shared with
the macOS build.

%prep
%autosetup -n %{name}-%{version}

%build
swift build -c release --disable-sandbox

%install
install -d %{buildroot}%{privdir}
install -m 0755 .build/release/Vitrine %{buildroot}%{privdir}/Vitrine

# SwiftPM emits each target's declared resources — the splash paintings — as a
# bundle beside the executable, and Bundle.module looks for it there. The two
# travel together or the cards lose their artwork.
for bundle in .build/release/*.bundle; do
    cp -r "$bundle" %{buildroot}%{privdir}/
done

# A wrapper rather than a symlink: Bundle.module resolves its search path from
# the running executable, and a symlink from %{_bindir} would send it looking
# in the wrong directory.
install -d %{buildroot}%{_bindir}
cat > %{buildroot}%{_bindir}/%{name} <<EOF
#!/usr/bin/sh
exec %{privdir}/Vitrine "\$@"
EOF
chmod 0755 %{buildroot}%{_bindir}/%{name}

install -Dm 0644 packaging/fedora/%{appid}.desktop \
    %{buildroot}%{_datadir}/applications/%{appid}.desktop
install -Dm 0644 packaging/fedora/%{appid}.metainfo.xml \
    %{buildroot}%{_metainfodir}/%{appid}.metainfo.xml

for size in 128x128 256x256 512x512; do
    install -Dm 0644 packaging/fedora/icons/$size/%{appid}.png \
        %{buildroot}%{_datadir}/icons/hicolor/$size/apps/%{appid}.png
done

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/%{appid}.desktop
appstream-util validate-relax --nonet %{buildroot}%{_metainfodir}/%{appid}.metainfo.xml

%files
%doc README.md
%{_bindir}/%{name}
%{privdir}/
%{_datadir}/applications/%{appid}.desktop
%{_metainfodir}/%{appid}.metainfo.xml
%{_datadir}/icons/hicolor/*/apps/%{appid}.png

%changelog
* Tue Sep 15 2026 Claxon <claxon@users.noreply.github.com> - 1.1-1
- Update to 1.1.

* Fri Sep 11 2026 Claxon <claxon@users.noreply.github.com> - 1.0-1
- First Fedora package.
