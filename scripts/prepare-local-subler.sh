#!/bin/bash
# Fetch pristine pinned sources and apply the reviewed local-only source patches.
set -euo pipefail
cd "$(dirname "$0")/.."
source_root="$PWD/vendor-local/Subler"
patch_root="$PWD/patches/local-subler"
if [ -e "$source_root" ]; then
    printf '%s\n' 'Source checkout already exists; refusing to replace or reset it.' >&2
    exit 2
fi
mkdir -p "$PWD/vendor-local"
git clone --no-checkout https://github.com/SublerApp/Subler.git "$source_root"
git -C "$source_root" checkout --detach 9077b6d149be621ff7d7b0d8eb46839a56610844
git -C "$source_root" submodule update --init MP42Foundation
git -C "$source_root/MP42Foundation" fetch origin bfa477b799ce55716f744638e6dfe3f23d39c5d7
git -C "$source_root/MP42Foundation" checkout --detach bfa477b799ce55716f744638e6dfe3f23d39c5d7
git -C "$source_root/MP42Foundation" submodule update --init --recursive
[ "$(git -C "$source_root/MP42Foundation/contrib" rev-parse HEAD)" = debd14253dba88addfd918d144fb7872a9e075f7 ]
git -C "$source_root" apply --check "$patch_root/subler.patch"
git -C "$source_root/MP42Foundation" apply --check "$patch_root/mp42foundation.patch"
git -C "$source_root" apply "$patch_root/subler.patch"
git -C "$source_root" apply --check "$patch_root/graceful-quit.patch"
git -C "$source_root" apply "$patch_root/graceful-quit.patch"
git -C "$source_root" apply --check "$patch_root/background-audio-conversion.patch"
git -C "$source_root" apply "$patch_root/background-audio-conversion.patch"
git -C "$source_root/MP42Foundation" apply "$patch_root/mp42foundation.patch"
printf '%s\n' 'Pinned local-only sources prepared. See docs/local-subler-background.md before building.'
