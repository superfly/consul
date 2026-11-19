#!/bin/bash
# Build bundle.tar.gz from this checkout: bin/consul, a static linux/amd64
# binary, and VERSION, the version that binary reports.
#
# The binary is built from the newest commit that changes anything outside
# .buildkite/, so a commit that only touches the packaging publishes the same
# consul under a new bundle.
#
# A Go binary records the paths it was compiled at, the toolchain's included,
# so those are part of its bytes. The build runs at the paths below, on the
# toolchain below, because they are the ones the 1.12.0-fly3 release was built
# with: for that source commit the result is the released binary, byte for
# byte, and the build fails if it is anything else.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

GO_IMAGE=golang:1.19.3@sha256:10e3c0f39f8e237baa5b66c5295c578cac42a99536cc9333d8505324a82407d9
BUILD_GOROOT=/usr/lib/go-1.19
BUILD_GOPATH=/home/will/go
BUILD_DIR=/home/will/fly/consul

# Source commits whose binary is known, and its sha256.
declare -A KNOWN_SHA256=(
  # 1.12.0-fly3
  [b560108eea25a2a13ea8a5432a23f1185fd4ec53]=57fd61c6ce7a49a926fa3b3ef91f926d13592d72a6086dd0c97fb29bf1c48900
)

source_commit=$(git log -1 --format=%H -- . ':(exclude).buildkite')
test -n "$source_commit"
echo "Building consul from $source_commit"

rm -rf bundle bundle.tar.gz source.git
mkdir -p bundle/bin

# A clone of the source commit goes to the build path in the container, which
# leaves this checkout untouched and gives the binary the VCS stamp of the
# commit it is built from. source.git holds its objects whole, whatever this
# checkout borrows them from. The container runs as root to put the toolchain
# at its path, and hands the binary back to the calling user.
git clone --quiet --bare --dissociate . source.git
trap 'rm -rf source.git' EXIT

docker run --rm \
  --volume "$PWD/source.git:/repo.git:ro" \
  --volume "$PWD/bundle/bin:/out" \
  --env SOURCE_COMMIT="$source_commit" \
  --env BUILD_GOROOT="$BUILD_GOROOT" --env BUILD_GOPATH="$BUILD_GOPATH" --env BUILD_DIR="$BUILD_DIR" \
  --env OUT_OWNER="$(id -u):$(id -g)" \
  "$GO_IMAGE" bash -euo pipefail -c '
    mkdir -p "$(dirname "$BUILD_GOROOT")" "$(dirname "$BUILD_DIR")" "$BUILD_GOPATH"
    cp -a /usr/local/go "$BUILD_GOROOT"
    export GOROOT="$BUILD_GOROOT" GOPATH="$BUILD_GOPATH" PATH="$BUILD_GOROOT/bin:$PATH"

    git config --global --add safe.directory "*"
    git clone --quiet --no-checkout /repo.git "$BUILD_DIR"
    cd "$BUILD_DIR"
    git checkout --quiet "$SOURCE_COMMIT"

    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/consul \
      -ldflags "-X github.com/hashicorp/consul/version.GitCommit=${SOURCE_COMMIT:0:10}"
    chown "$OUT_OWNER" /out/consul
  '

known=${KNOWN_SHA256[$source_commit]-}
if [ -n "$known" ]; then
  echo "$known  bundle/bin/consul" | sha256sum --check -
fi

# "Consul v1.12.0-fly3" and "Revision b560108eea" become "v1.12.0-fly3 b560108eea".
bundle/bin/consul version | awk 'NR==1 {version=$2} NR==2 {print version, $2}' > bundle/VERSION
test -s bundle/VERSION

tar --sort=name --owner=0 --group=0 --numeric-owner --mode=go-w \
  -C bundle -czf bundle.tar.gz bin VERSION
