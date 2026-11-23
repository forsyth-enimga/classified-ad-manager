#!/usr/bin/env bash
# Builds a .deb from the Flutter Linux release bundle.
#   flutter build linux --release
#   bash packaging/linux/build_deb.sh [version]
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION="${1:-1.0.0}"
BUNDLE="build/linux/x64/release/bundle"
NAME="classified-ad-manager"
STAGE="build/deb/${NAME}_${VERSION}_amd64"

[ -d "$BUNDLE" ] || { echo "Missing $BUNDLE - run 'flutter build linux --release' first"; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$STAGE/opt/$NAME" "$STAGE/usr/bin" "$STAGE/usr/share/applications"

cp -r "$BUNDLE"/. "$STAGE/opt/$NAME/"
ln -s "/opt/$NAME/classified_ad_manager" "$STAGE/usr/bin/$NAME"

cat > "$STAGE/usr/share/applications/$NAME.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Classified Ad Manager
Comment=Manage classified ads and export them for Kijiji, eBay, Facebook Marketplace and more
Exec=/usr/bin/$NAME
Terminal=false
Categories=Office;Utility;
DESKTOP

cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: $NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libsqlite3-0
Recommends: zenity
Maintainer: Classified Ad Manager <noreply@example.com>
Description: Classified ad manager with per-platform text export
 Keep your classified ads in a local database and export them as text files
 formatted for Kijiji, eBay, Facebook Marketplace, VarageSale, Karrot,
 Poshmark and Depop.
CONTROL

dpkg-deb --build --root-owner-group "$STAGE" "build/deb/${NAME}_${VERSION}_amd64.deb"
echo "Built build/deb/${NAME}_${VERSION}_amd64.deb"
