#!/bin/bash
# Sets up a Linux box (Ubuntu 24.04, x86-64) to run Game of Crowns the way the Mac does:
# Godot 4.7.1, Freeciv 3.2.6 (the Mac's version; Ubuntu 24.04 only ships 3.1, which can't read its saves),
# and stand-ins for the Mac-only bits the tools use (`arch -arm64 godot`, zsh, a screen to render on).
# Run as root. Idempotent.
#   packaging/linux-setup.sh
# Then: start the bridge with packaging/linux-bridge.sh, and render with realm/tools/render.sh as on the Mac.
# The third-party art (realm/assets/{people,anims,props,...}) is not in git: see README "Assets".
set -euo pipefail
GODOT_VER=4.7.1-stable
FC=/opt/freeciv
UB=http://archive.ubuntu.com/ubuntu/pool

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq zsh xvfb x11-utils mesa-vulkan-drivers libvulkan1 ffmpeg >/dev/null

# Godot, the official Linux build.
if [ ! -x /opt/godot/Godot_v${GODOT_VER}_linux.x86_64 ]; then
  mkdir -p /opt/godot && cd /opt/godot
  curl -sL -o g.zip "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VER}/Godot_v${GODOT_VER}_linux.x86_64.zip"
  unzip -oq g.zip && rm g.zip
fi
# `godot`: windowed runs (renders, films, play) get a virtual screen and Mesa's software Vulkan when
# there's no display; --headless runs go straight through.
cat > /usr/local/bin/godot <<EOF
#!/bin/sh
G=/opt/godot/Godot_v${GODOT_VER}_linux.x86_64
case " \$* " in *" --headless "*) exec "\$G" "\$@";; esac
if [ -z "\$DISPLAY" ]; then
  export DISPLAY=:99
  [ -e /tmp/.X11-unix/X99 ] || { nohup Xvfb :99 -screen 0 2560x1440x24 -nolisten tcp >/tmp/xvfb99.log 2>&1 & sleep 2; }
fi
export VK_ICD_FILENAMES=\${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}
exec "\$G" "\$@"
EOF
chmod +x /usr/local/bin/godot

# `arch -arm64 godot ...` (every tool's launch line on the Mac) runs the command as is here.
cat > /usr/local/bin/arch <<'EOF'
#!/bin/sh
case "$1" in -*) shift; exec "$@";; "") exec uname -m;; *) exec "$@";; esac
EOF
chmod +x /usr/local/bin/arch

# Freeciv 3.2.6 server from Ubuntu's own package (built for a newer release), with the ICU it needs
# kept beside it rather than replacing the system's.
if [ ! -x $FC/freeciv-server.bin ]; then
  T=$(mktemp -d) && cd "$T"
  curl -s -O $UB/universe/f/freeciv/freeciv-server_3.2.6+ds-1_amd64.deb
  curl -s -O $UB/universe/f/freeciv/freeciv-data_3.2.6+ds-1_all.deb
  ICU=$(curl -s $UB/main/i/icu/ | grep -o 'libicu78_[^"<]*_amd64\.deb' | sort -u | tail -1)
  curl -s -O $UB/main/i/icu/$ICU
  for d in *.deb; do dpkg-deb -x "$d" x; done
  mkdir -p $FC/lib $FC/share
  cp -a x/usr/lib/x86_64-linux-gnu/libicu*.so.78* $FC/lib/
  cp -a x/usr/games/freeciv-server $FC/freeciv-server.bin
  cp -a x/usr/share/games/freeciv $FC/share/
  cd / && rm -rf "$T"
fi
# Freeciv refuses to run as root; the bridge's server runs as the unprivileged `realm` user.
id realm >/dev/null 2>&1 || useradd -M -s /usr/sbin/nologin realm
cat > $FC/freeciv-server <<'EOF'
#!/bin/sh
export LD_LIBRARY_PATH=/opt/freeciv/lib
if [ "$(id -u)" = 0 ]; then exec runuser -u realm --preserve-environment -- /opt/freeciv/freeciv-server.bin "$@"; fi
exec /opt/freeciv/freeciv-server.bin "$@"
EOF
chmod +x $FC/freeciv-server
$FC/freeciv-server --version
godot --version
