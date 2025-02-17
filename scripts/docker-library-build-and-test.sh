#!/usr/bin/env bash

set -xeuvo pipefail

# container builds copy permissions and
# depend on go+rx permissions
umask 0002
if [ -d mariadb-docker ]; then
  pushd mariadb-docker
  git fetch
  git checkout origin/next
  popd
else
  git clone --branch next https://github.com/MariaDB/mariadb-docker.git
  pushd mariadb-docker
  git config pull.ff only
  popd
fi

tarbuildnum=${1}
mariadb_version=${2}
mariadb_version=${mariadb_version#*-}
buildername=${3:-amd64-ubuntu-2004-deb-autobake}
master_branch=${mariadb_version%\.*}
commit=${4:-0}
branch=${5:-${master_branch}}

if [[ ! $branch =~ ^preview ]] &&
  [[ ! $branch =~ ^[[:digit:]]+\.[[:digit:]]+$ ]] &&
  [[ ! $branch =~ ^bb-[[:digit:]]+\.[[:digit:]]+-release ]]; then
  exit 0
fi

# keep in sync with docker-cleanup script
if [[ $branch =~ ^preview ]]; then
  container_tag=${branch#preview-}
  feature=${branch#preview-[0-9]*\.[0-9]*-}
  feature="${feature%_triggerBB}"
else
  container_tag=$master_branch
  feature=""
fi
# Container tags must be lower case.
container_tag=${container_tag,,*}

case "${buildername#*ubuntu-}" in
  2204-deb-autobake)
    base=jammy
    pkgver=ubu2204
    ;;
  2004-deb-autobake)
    base=focal
    pkgver=ubu2204
    ;;
  *)
    echo "unknown base buildername $buildername"
    exit 0
    ;;
esac

# gradually exclude for other major version as
# https://github.com/MariaDB/server/commit/c168e16782fc449f61412e5afc1c01d59b77c675
# is merged up.
case "$container_tag" in
  10.3)
    ;;
  *)
    pkgver=$base
    ;;
esac

buildernamebase=${buildername#*-}
builderarch=${buildername%%-*}

declare -a annotations=(
  "--annotation" "org.opencontainers.image.authors=MariaDB Foundation"
  "--annotation" "org.opencontainers.image.documentation=https://hub.docker.com/_/mariadb"
  "--annotation" "org.opencontainers.image.source=https://github.com/MariaDB/mariadb-docker/tree/$(
    cd "mariadb-docker/$master_branch"
    git rev-parse HEAD
  )/$master_branch"
  "--annotation" "org.opencontainers.image.licenses=GPL-2.0"
  "--annotation" "org.opencontainers.image.title=MariaDB Server $container_tag CI build"
  "--annotation" "org.opencontainers.image.description=This is not a Release.\nBuild of the MariaDB Server from CI as of commit $commit"
  "--annotation" "org.opencontainers.image.version=$mariadb_version+$commit"
  "--annotation" "org.opencontainers.image.revision=$commit")

annotate() {
  for item in "${annotations[@]}"; do
    echo " --annotation" \""$item"\"
  done
}

# Annotations - https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
build() {
  arch=$1
  shift
  t=$(mktemp)
  buildah bud --layers "$@" --build-arg REPOSITORY="[trusted=yes] https://ci.mariadb.org/$tarbuildnum/${arch}-${buildernamebase}/debs ./" \
    --build-arg MARIADB_VERSION="1:$mariadb_version+maria~$pkgver" \
    "${annotations[@]}" \
    "mariadb-docker/$master_branch" | tee "${t}"
  image=$(tail -n 1 "$t")
  rm "$t"
}

#
# BUILD Image

if [ "${builderarch}" = aarch64 ]; then
  build aarch64 --arch arm64 --variant v8
else
  build "${builderarch}" --arch "${builderarch}"
fi

#
# TEST Image
#

if [ "${builderarch}" != amd64 ]; then
  export DOCKER_LIBRARY_START_TIMEOUT=350
else
  export DOCKER_LIBRARY_START_TIMEOUT=150
fi

# NO_TEST for manual invocation
if [ -n "${NO_TEST:-}" ]; then
  echo "Skipping test"
else
  # clean images if test does not succeed
  trap 'buildah rmi "$image"' EXIT
  mariadb-docker/.test/run.sh "$image"
fi

# restrict pushing of images to preview, main, and release branches
if [[ ! $branch =~ ^preview ]] &&
  [[ ! $branch =~ ^[[:digit:]]+\.[[:digit:]]+$ ]] &&
  [[ ! $branch =~ ^bb-[[:digit:]]+\.[[:digit:]]+-release ]]; then
  buildah rmi "$image"
  exit 0
fi

origbuildimage=$image
#
# METADATA:

# Add manifest file of version and fix mariadb version in the configuration
# because otherwise 'buildah manifest add "$devmanifest" "$image"' would be sufficient

container=$(buildah from "$image")
manifestfile=$(mktemp)
for item in "${annotations[@]}"; do
  [ "$item" != "--annotation" ] && echo -e "$item\n"
done >"$manifestfile"
buildah copy --add-history "$container" "$manifestfile" /manifest.txt
rm -f "$manifestfile"

#
# MAKE it part of the mariadb-devel manifest
#

buildmanifest() {
  base=$1
  shift
  manifest=$1
  shift
  container=$1
  shift
  # create a manifest, and if it already exists, remove the one for the
  # current architecture as we're replacing this.
  # This could happen due to triggered rebuilds on buildbot.

  buildah manifest create "$manifest" || buildah manifest inspect "$manifest" |
    jq ".manifests[] | select( .platform.architecture == \"$builderarch\") | .digest" |
    xargs --no-run-if-empty -n 1 buildah manifest remove "$manifest"

  t=$(mktemp)
  buildah commit "$@" --iidfile "$t" --manifest "$manifest" "$container"
  image=$(<"$t")
  ##buildah push --rm "$image" "docker://quay.io/mariadb-foundation/${base}:${container_tag}-${builderarch}" &&
  ##  buildah rmi "$image"
  # $image is the wrong sha for annotation. Config vs Blog?
  # Even below doesn't annotate manifest. Unknown reason, doesn't error
  buildah manifest inspect "$manifest" |
    jq ".manifests[] | select( .platform.architecture == \"$builderarch\") | .digest" |
    xargs --no-run-if-empty -n 1 buildah manifest annotate \
      "${annotations[@]}" \
      "$manifest"
  rm -f "$t"
}

devmanifest=mariadb-devel-${container_tag}-$commit

trap 'buildah rm "$container"' EXIT
buildmanifest mariadb-devel "$devmanifest" "$container"

#
# MAKE Debug manifest

# linux-tools-common for perf
buildah run --add-history "$container" sh -c \
  "apt-get update \
	&& apt-get install -y linux-tools-common gdbserver gdb curl \
	&& dpkg-query  --showformat='\${Package},\${Version},\${Architecture}\n' --show | grep mariadb \
	| while IFS=, read  pkg version arch; do \
          [ \$arch != all ] && apt-get install -y \${pkg}-dbgsym=\${version} ;
        done; \
	rm -rf /var/lib/apt/lists/*"

debugmanifest=mariadb-debug-${container_tag}-$commit

buildmanifest mariadb-debug "$debugmanifest" "$container" --rm

buildah rmi "$origbuildimage"

if [[ $master_branch =~ 10.[234] ]]; then
  expected=3
else
  expected=4
fi

#
#
# PUSHIT - if the manifest if complete, i.e. all supported arches are there, we push
#

manifest_image_cleanup() {
  t=$1
  # A manifest is an image type that podman can remove
  podman images --filter dangling=true --format '{{.ID}} {{.Digest}}' |
    while read -r line; do
      id=${line% *}
      digest=${line#* }
      echo id="$id" digest="$digest"
      if [ -n "$(jq ".manifests[].digest  |select(. == \"$digest\")" <"$t")" ]; then
        podman rmi "$id"
      fi
    done
  rm "$t"
}

if (($(buildah manifest inspect "$devmanifest" | jq '.manifests | length') >= expected)); then
  container_tag=${container_tag%_triggerbb}
  t=$(mktemp)
  buildah manifest inspect "$devmanifest" | tee "${t}"
  trap 'manifest_image_cleanup "$t"' EXIT
  buildah manifest push --all --rm "$devmanifest" "docker://quay.io/mariadb-foundation/mariadb-devel:${container_tag}"
  manifest_image_cleanup "$t"

  t=$(mktemp)
  buildah manifest inspect "$debugmanifest" | tee "${t}"
  trap 'manifest_image_cleanup "$t"' EXIT
  buildah manifest push --all --rm "$debugmanifest" "docker://quay.io/mariadb-foundation/mariadb-debug:${container_tag}"
  manifest_image_cleanup "$t"

  buildah images
  # lost and forgotten (or just didn't make enough manifest items - build failure on an arch)
  # Note *: coming to a buildah update sometime - epnoc timestamps - https://github.com/containers/buildah/pull/3482
  lastweek=$(date +%s --date='1 week ago')
  # old ubuntu and base images that got updated so are Dangling
  podman images --format=json | jq ".[] | select(.Created <= $lastweek and .Dangling) | .Id" | xargs --no-run-if-empty podman rmi || echo "continuing cleanup anyway"
  # clean buildah containers
  buildah containers --format "{{.ContainerID}}" | xargs --no-run-if-empty buildah rm
  # clean images
  # (Note *) buildah images --json |  jq ".[] | select(.readonly ==false) |  select(.created <= $lastweek) | select( .names == null) | .id" | xargs --no-run-if-empty buildah rmi
  buildah images --json | jq ".[] | select(.readonly ==false) |  select(.createdatraw | sub(\"(?<full>[^.]*).[0-9]+Z\"; \"\\(.full)Z\") | fromdateiso8601 <= $lastweek) | select( .names == null) | .id" | xargs --no-run-if-empty buildah rmi
  # clean manifests
  # (Note *) buildah images --json |  jq ".[] | select(.readonly ==false) |  select(.created <= $lastweek) | select( try .names[0]? catch \"\" | startswith(\"localhost/mariadb-\") ) | .id" | xargs --no-run-if-empty buildah manifest rm
  buildah images --json | jq ".[] | select(.readonly ==false) |  select(.createdatraw | sub(\"(?<full>[^.]*).[0-9]+Z\"; \"\\(.full)Z\") | fromdateiso8601 <= $lastweek) | select( try .names[0]? catch \"\" | startswith(\"localhost/mariadb-\") ) | .id" | xargs --no-run-if-empty buildah manifest rm
  buildah images
fi

trap - EXIT
