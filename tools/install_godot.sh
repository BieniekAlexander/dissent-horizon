#!/bin/bash
# Installs the Godot editor binary this project targets, headless-capable, as `godot` on PATH.
#
# Which version: project.godot's `config/features` names the engine major.minor ("4.7"), and the
# editor rewrites it whenever the project is opened in a newer engine — so bumping Godot needs
# no edit here. A patch release cannot be named there, so an optional one-line `.godot-version`
# at the repo root (e.g. `4.7.1-stable`) pins it; its major.minor must agree with project.godot.
#
# Idempotent: exits at once when the installed binary already reports the wanted version.
# Env: GODOT_INSTALL_ROOT (default /opt/godot) holds one directory per version;
#      GODOT_BIN_LINK (default /usr/local/bin/godot) is the symlink pointed at the active one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_ROOT="${GODOT_INSTALL_ROOT:-/opt/godot}"
BIN_LINK="${GODOT_BIN_LINK:-/usr/local/bin/godot}"
RELEASES="https://github.com/godotengine/godot-builds/releases/download"

features_version="$(sed -nE 's/^config\/features=PackedStringArray\("([0-9]+\.[0-9]+)".*/\1/p' "$ROOT/project.godot" | head -n1)"
if [ -z "$features_version" ]; then
  echo "install_godot: no engine version in project.godot config/features" >&2
  exit 1
fi

tag="${features_version}-stable"
if [ -f "$ROOT/.godot-version" ]; then
  tag="$(tr -d '[:space:]' < "$ROOT/.godot-version")"
  case "$tag" in
    "$features_version"-*|"$features_version".*) ;;
    *)
      echo "install_godot: .godot-version ($tag) disagrees with project.godot ($features_version)" >&2
      exit 1
      ;;
  esac
fi

# `godot --version` prints e.g. "4.7.stable.official.<hash>" for tag "4.7-stable".
expected_prefix="${tag/-/.}"
if command -v godot >/dev/null 2>&1 && [[ "$(godot --version 2>/dev/null || true)" == "$expected_prefix".* ]]; then
  echo "install_godot: Godot $tag already installed"
  exit 0
fi

asset="Godot_v${tag}_linux.x86_64"
dest="$INSTALL_ROOT/$tag"
if [ ! -x "$dest/$asset" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "install_godot: downloading Godot $tag"
  curl -fsSL --retry 4 --retry-delay 2 -o "$tmp/$asset.zip" "$RELEASES/$tag/$asset.zip"
  curl -fsSL --retry 4 --retry-delay 2 -o "$tmp/SHA512-SUMS.txt" "$RELEASES/$tag/SHA512-SUMS.txt"
  expected_sum="$(awk -v f="$asset.zip" '$2 == f { print $1 }' "$tmp/SHA512-SUMS.txt")"
  actual_sum="$(sha512sum "$tmp/$asset.zip" | cut -d' ' -f1)"
  if [ -z "$expected_sum" ] || [ "$expected_sum" != "$actual_sum" ]; then
    echo "install_godot: checksum mismatch for $asset.zip" >&2
    exit 1
  fi
  mkdir -p "$dest"
  unzip -q -o "$tmp/$asset.zip" -d "$dest"
  chmod +x "$dest/$asset"
fi

mkdir -p "$(dirname "$BIN_LINK")"
ln -sf "$dest/$asset" "$BIN_LINK"
echo "install_godot: $("$BIN_LINK" --version) -> $BIN_LINK"
