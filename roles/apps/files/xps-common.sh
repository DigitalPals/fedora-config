# Shared helpers for the XPS upstream installer scripts.
# Source this file; do not execute it. Installed at /usr/local/libexec/xps-common.sh.
# shellcheck shell=bash

# gh_api_fetch <url> <cache_dir> <out_file>
# GitHub API GET with ETag caching. A 304 reuses the cached body and does not
# count against the anonymous rate limit. GH_TOKEN is honored when set.
gh_api_fetch() {
  local url=$1 cache_dir=$2 out=$3
  local headers=(-H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28')
  [[ -z ${GH_TOKEN:-} ]] || headers+=(-H "Authorization: Bearer $GH_TOKEN")
  mkdir -p "$cache_dir"
  local etag="$cache_dir/etag" body="$cache_dir/response.json" code
  local compare=()
  [[ -r $etag && -s $body ]] && compare=(--etag-compare "$etag")
  code=$(curl --silent --show-error --location "${headers[@]}" "${compare[@]}" \
    --etag-save "$etag.new" --write-out '%{http_code}' \
    --output "$body.new" "$url") || {
    rm -f "$etag.new" "$body.new"
    echo "GitHub API request failed for $url. Set GH_TOKEN if the anonymous limit was reached." >&2
    return 1
  }
  if [[ $code == 200 && -s $body.new ]]; then
    mv -f "$body.new" "$body"
    if [[ -s $etag.new ]]; then mv -f "$etag.new" "$etag"; else rm -f "$etag.new" "$etag"; fi
  elif [[ $code == 304 ]]; then
    rm -f "$body.new" "$etag.new"
  else
    rm -f "$body.new" "$etag.new"
    echo "GitHub API returned HTTP $code for $url. Set GH_TOKEN if the anonymous limit was reached." >&2
    return 1
  fi
  cat "$body" >"$out"
}

# atomic_current_swap <root> <relative_target>
# Repoint <root>/current at <relative_target> without a broken-link window.
atomic_current_swap() {
  local root=$1 target=$2
  ln -sfn "$target" "$root/current.new"
  mv -Tf "$root/current.new" "$root/current"
}

# verify_sha256 <file> <expected_hex>
verify_sha256() {
  local actual
  actual=$(sha256sum "$1" | awk '{print $1}')
  [[ $actual == "$2" ]]
}

emit_changed() { echo "CHANGED: $*"; }
emit_unchanged() { echo "UNCHANGED: $*"; }

xps_restorecon() { restorecon -RF "$@" 2>/dev/null || true; }
