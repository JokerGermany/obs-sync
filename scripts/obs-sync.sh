#!/usr/bin/env bash
# Upload the newest release of every app in apps.txt to an Open Build Service project
# as one OBS package with deb (.dsc), rpm (.spec) and Arch (PKGBUILD) recipes.
#
# Environment:
#   OBS_PROJECT    e.g. home:JokerGermany:apps                        (required)
#   OBS_APIURL     default: https://api.opensuse.org
#   DEBFULLNAME, DEBEMAIL                                             (required unless DRY_RUN=1)
#   APPS_FILE      default: apps.txt
#   STATE_FILE     default: state/published.txt
#   RPM_REGEX      default: x86_64\.rpm$
#   ARCH_REGEX     default: x86_64\.pkg\.tar\.zst$
#   ONLY (substring filter), DRY_RUN (1 = report only), GH_TOKEN (optional)
# osc must be configured with credentials for OBS_APIURL (not needed for DRY_RUN=1).

set -uo pipefail
APPS_FILE="${APPS_FILE:-apps.txt}"
STATE_FILE="${STATE_FILE:-state/published.txt}"
OBS_APIURL="${OBS_APIURL:-https://api.opensuse.org}"
RPM_REGEX="${RPM_REGEX:-x86_64\\.rpm\$}"
ARCH_REGEX="${ARCH_REGEX:-x86_64\\.pkg\\.tar\\.zst\$}"
DRY_RUN="${DRY_RUN:-0}"; ONLY="${ONLY:-}"
: "${OBS_PROJECT:?set OBS_PROJECT, e.g. home:JokerGermany:apps}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="${RUNNER_TEMP:-/tmp}/obs-sync"
mkdir -p "$(dirname "$STATE_FILE")"; touch "$STATE_FILE"

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; echo "${s%"${s##*[![:space:]]}"}"; }
gh_api() {
  local a=(-fsSL -H "Accept: application/vnd.github+json")
  [ -n "${GH_TOKEN:-}" ] && a+=(-H "Authorization: Bearer $GH_TOKEN")
  curl "${a[@]}" "https://api.github.com/$1"
}
asset() {  # $1 = release json, $2 = regex -> "name url" of first match
  jq -r --arg re "$2" '[.assets[] | select(.name|test($re))][0] // empty | "\(.name) \(.browser_download_url)"' <<<"$1"
}
fetch_checked() {  # $1 = url, $2 = target, $3 = sums file (may be missing)
  curl -fsSL -o "$2" "$1" || return 1
  [ -f "$3" ] || { echo "WARNING: no checksum file for $(basename "$2")"; return 0; }
  local exp act
  exp="$(awk -v f="$(basename "$2")" '{n=$2; sub(/^\*/,"",n); if (n==f) print $1}' "$3")"
  act="$(sha256sum "$2" | awk '{print $1}')"
  [ -n "$exp" ] && [ "$exp" = "$act" ] || { echo "ERROR: checksum mismatch for $(basename "$2")"; return 1; }
}
obs() { osc -A "$OBS_APIURL" api "$@"; }
obs_upload() {  # $1 = package, $2 = dir, $3 = comment
  local pkg="$1" dir="$2" c f old
  c="$(jq -rn --arg s "$3" '$s|@uri')"
  if ! obs "/source/$OBS_PROJECT/$pkg/_meta" >/dev/null 2>&1; then
    obs -X PUT -d "<package name=\"$pkg\" project=\"$OBS_PROJECT\"><title>$pkg</title><description>Unofficial repackage of upstream release files.</description></package>" \
      "/source/$OBS_PROJECT/$pkg/_meta" >/dev/null || return 1
  fi
  old="$(obs "/source/$OBS_PROJECT/$pkg" | grep -o '<entry name="[^"]*"' | cut -d'"' -f2)"
  for f in "$dir"/*; do
    echo "  upload $(basename "$f")"
    obs -X PUT -f "$f" "/source/$OBS_PROJECT/$pkg/$(basename "$f")?comment=$c" >/dev/null || return 1
  done
  for f in $old; do   # remove files of the previous version
    [ -e "$dir/$f" ] && continue
    echo "  delete $f"
    obs -X DELETE "/source/$OBS_PROJECT/$pkg/$f?comment=$c" >/dev/null || return 1
  done
}

failed=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"; [ -z "$(trim "$line")" ] && continue
  IFS='|' read -r repo license regex sums <<<"$line"
  repo="$(trim "$repo")"; license="$(trim "$license")"; regex="$(trim "$regex")"; sums="$(trim "${sums:-required}")"
  [ -n "$ONLY" ] && [[ "$repo" != *"$ONLY"* ]] && continue
  echo "::group::$repo"

  rel="$(gh_api "repos/$repo/releases?per_page=20" | jq -c '[.[] | select(.draft==false and .prerelease==false)] | first // empty')"
  if [ -z "$rel" ]; then echo "ERROR: no release / API error"; failed+=("$repo"); echo "::endgroup::"; continue; fi
  tag="$(jq -r .tag_name <<<"$rel")"
  deb_a="$(asset "$rel" "$regex")"; rpm_a="$(asset "$rel" "$RPM_REGEX")"; arch_a="$(asset "$rel" "$ARCH_REGEX")"
  echo "latest: $tag | deb: ${deb_a%% *} | rpm metadata: ${rpm_a%% *} | arch metadata: ${arch_a%% *}"

  if grep -q "^$repo $tag " "$STATE_FILE"; then echo "already uploaded"; echo "::endgroup::"; continue; fi
  if [ "$DRY_RUN" = "1" ]; then echo "DRY RUN: would upload $repo $tag"; echo "::endgroup::"; continue; fi
  [ -n "$deb_a" ] || { echo "ERROR: no .deb"; failed+=("$repo"); echo "::endgroup::"; continue; }

  work="$BASE/$(tr / _ <<<"$repo")"; rm -rf "$work"; mkdir -p "$work/up"
  ok=1
  GH_REPO="$repo" ASSET_REGEX="$regex" LICENSE="$license" REQUIRE_SUMS="$([ "$sums" = optional ] && echo 0 || echo 1)" \
    WORKDIR="$work/src" "$HERE/make-source-package.sh" || ok=0
  sumsfile="$work/src/dl/SHA256SUMS.txt"
  rpm_f=""; arch_f=""
  if [ "$ok" = 1 ] && [ -n "$rpm_a" ]; then
    rpm_f="$work/up/${rpm_a%% *}"; fetch_checked "${rpm_a#* }" "$rpm_f" "$sumsfile" || ok=0
  fi
  if [ "$ok" = 1 ] && [ -n "$arch_a" ]; then
    arch_f="$work/up/${arch_a%% *}"; fetch_checked "${arch_a#* }" "$arch_f" "$sumsfile" || ok=0
  fi
  if [ "$ok" = 1 ]; then
    RPM="$rpm_f" ARCHPKG="$arch_f" LICENSE="$license" GH_REPO="$repo" \
      "$HERE/make-obs-recipes.sh" "$work/src" "$work/obs" || ok=0
  fi
  if [ "$ok" = 1 ]; then
    # shellcheck disable=SC1091
    . "$work/src/result.env"
    obs_upload "$PKG" "$work/obs" "Update to upstream $tag" || ok=0
  fi

  if [ "$ok" = 1 ]; then echo "$repo $tag ${SRCVER} $(date -u +%F)" >> "$STATE_FILE"
  else echo "ERROR: $repo $tag failed"; failed+=("$repo"); fi
  rm -rf "$work"
  echo "::endgroup::"
done < "$APPS_FILE"

if [ ${#failed[@]} -gt 0 ]; then echo "FAILED: ${failed[*]}"; exit 1; fi
echo "all done"
