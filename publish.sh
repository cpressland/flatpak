#!/bin/bash
# Make the Flatpak repository players install from, as a static site:
#
#   ./publish.sh SITE REPO...
#
# Each REPO is an OSTree repository a game's build made (flatpak-builder
# --repo), unsigned, of any of the apps in apps.json and any architecture.
# SITE gets:
#   repo/                  the OSTree repository, signed: every app, every arch
#   APP-ID.flatpakref      each app's one-click install (adds the remote)
#   cpressland.flatpakrepo the remote alone
#   index.html             how to install
# It holds each app's latest build only: an update pulls what changed, and
# static deltas make a fresh install one download.
#
# FLATPAK_GPG_PRIVATE_KEY: the armoured signing key (its public half is
# flatpak-signing-key.asc). FLATPAK_URL: where SITE is served
# (https://flatpak.cpressland.io).
set -euo pipefail

[ $# -ge 2 ] || { sed -n '2,18p' "$0"; exit 2; }
: "${FLATPAK_GPG_PRIVATE_KEY:?the signing key}"
here=$(cd "$(dirname "$0")" && pwd)
url=${FLATPAK_URL:-https://flatpak.cpressland.io}
url=${url%/}
site=$1
shift

gpghome=$(mktemp -d)
trap 'rm -rf "$gpghome"' EXIT
chmod 700 "$gpghome"
printf '%s\n' "$FLATPAK_GPG_PRIVATE_KEY" | gpg --homedir "$gpghome" --batch --quiet --import
key=$(gpg --homedir "$gpghome" --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
pubkey=$(gpg --homedir "$gpghome" --export "$key" | base64 | tr -d '\n')

rm -rf "$site"
mkdir -p "$site"
ostree init --mode=archive-z2 --repo="$site/repo"
published=()
for id in $(jq -r '.[].id' "$here/apps.json"); do
  found=
  for r in "$@"; do
    for ref in $(ostree refs --repo="$r" | grep "^app/$id/" || true); do   # the app, not its Debug extension
      ostree pull-local --repo="$site/repo" "$r" "$ref"
      IFS=/ read -r _ _ arch branch <<< "$ref"
      flatpak build-sign "$site/repo" "$id" "$branch" --arch="$arch" --gpg-sign="$key" --gpg-homedir="$gpghome"
      echo "$ref"
      found=1
    done
  done
  [ -n "$found" ] && published+=("$id") || echo "warning: no build of $id" >&2
done
[ ${#published[@]} -gt 0 ] || { echo "no app to publish" >&2; exit 1; }
flatpak build-update-repo --gpg-sign="$key" --gpg-homedir="$gpghome" --generate-static-deltas \
  --title="cpressland" --default-branch=stable "$site/repo"

cat > "$site/cpressland.flatpakrepo" <<END
[Flatpak Repo]
Title=cpressland
Url=$url/repo/
Homepage=https://github.com/cpressland/flatpak
GPGKey=$pubkey
END

items=
for id in "${published[@]}"; do
  app=$(jq -c --arg id "$id" '.[] | select(.id == $id)' "$here/apps.json")
  name=$(jq -r .name <<< "$app"); summary=$(jq -r .summary <<< "$app"); repo=$(jq -r .repo <<< "$app")
  cat > "$site/$id.flatpakref" <<END
[Flatpak Ref]
Name=$id
Branch=stable
Title=$name
Url=$url/repo/
SuggestRemoteName=cpressland
RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo
IsRuntime=false
Homepage=https://github.com/$repo
GPGKey=$pubkey
END
  items+="<h2>$name</h2><p>$summary <a href=\"https://github.com/$repo\">Source</a>.</p>
<p><a href=\"$id.flatpakref\">Install $name</a> (opens your software centre), or from a terminal:</p>
<div class=\"cmd\"><pre>flatpak install --user $url/$id.flatpakref</pre><button type=\"button\" class=\"copy\">Copy</button></div>
"
done

cat > "$site/index.html" <<END
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>cpressland Flatpaks</title>
<style>body{font:16px/1.5 system-ui,sans-serif;max-width:40em;margin:3em auto;padding:0 1em}code,pre{background:#f2f0f7;border-radius:4px}pre{padding:.8em;overflow-x:auto}
.cmd{display:flex;gap:.5em;align-items:stretch;margin:1em 0}.cmd pre{flex:1;margin:0;white-space:pre-wrap;word-break:break-all}.copy{font:inherit;font-size:.9em;padding:0 1em;border:1px solid #c9c3d9;border-radius:4px;background:#fff;cursor:pointer}.copy:hover{background:#ece8f5}</style>
</head><body>
<h1>cpressland Flatpaks</h1>
<p>Recompiled PC games for any Linux, Steam Deck included. None of a game is in its Flatpak: the first run downloads it and builds it on your computer.</p>
$items
<h2>Steam Deck</h2>
<p>In Desktop Mode, run the install command in Konsole, then add the game to Steam (Add a Non-Steam Game) to play it from Game Mode.</p>
<p>Updates come with your other Flatpaks. The repository is signed with <a href="https://github.com/cpressland/flatpak/blob/main/flatpak-signing-key.asc">this key</a>.</p>
<script>
/* Copy buttons: the clipboard API where the page may use it, else a selection copied the old way. */
document.querySelectorAll(".copy").forEach(function (b) {
  b.addEventListener("click", function () {
    var text = b.parentNode.querySelector("pre").textContent;
    var done = function () { b.textContent = "Copied"; setTimeout(function () { b.textContent = "Copy"; }, 1500); };
    var old = function () {
      var t = document.createElement("textarea");
      t.value = text; t.setAttribute("readonly", ""); t.style.position = "fixed"; t.style.opacity = "0";
      document.body.appendChild(t); t.select();
      try { document.execCommand("copy"); done(); } catch (e) { b.textContent = "Select and copy"; }
      document.body.removeChild(t);
    };
    if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(done, old); else old();
  });
});
</script>
</body></html>
END
echo "==> $site ($url): ${published[*]}"
