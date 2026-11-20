# Sourced by the build scripts. Sets SWIFTC_FLAGS with a VFS overlay that works around a stale
# /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap ("redefinition of module
# 'SwiftBridging'") in some Command Line Tools installs. No system files are changed; harmless otherwise.
setup_swiftc() {
  mkdir -p "$APP_DIR/.build"
  : > "$APP_DIR/.build/empty.modulemap"
  cat > "$APP_DIR/.build/vfs.yaml" <<EOT
{ "version": 0, "roots": [ { "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap", "type": "file", "external-contents": "$APP_DIR/.build/empty.modulemap" } ] }
EOT
  SWIFTC_FLAGS=(-vfsoverlay "$APP_DIR/.build/vfs.yaml" -Xcc -ivfsoverlay -Xcc "$APP_DIR/.build/vfs.yaml")
}
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup_swiftc
