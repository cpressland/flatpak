# cpressland Flatpaks

The Flatpak repository at <https://flatpak.cpressland.io>: recompiled PC
games for Linux and the Steam Deck. None of a game is in its Flatpak; each
downloads the game and builds it on the player's computer. Players install
from a game's `.flatpakref`, which adds the `cpressland` remote:

```
flatpak install --user https://flatpak.cpressland.io/io.cpressland.ThemeParkWorld.flatpakref
```

Nothing is built here. Each game's own CI builds its Flatpak (x86-64 and
arm64) and attaches the OSTree repositories to a release named `flatpak` in
its repository, as `flatpak-x86_64.tar` and `flatpak-aarch64.tar`. Then
`.github/workflows/publish.yml` fetches every app's builds, and `publish.sh`
merges them into one repository, signs it with the `FLATPAK_GPG_PRIVATE_KEY`
secret (public half: `flatpak-signing-key.asc`) and deploys it to GitHub
Pages. The repository holds each app's latest build only.

## Adding a game

1. Its CI attaches `flatpak-ARCH.tar` (a tar of `flatpak-builder --repo`'s
   folder, as `repo/`) to its `flatpak` release, then runs
   `gh workflow run publish --repo cpressland/flatpak` with a token in its
   `FLATPAK_HUB_TOKEN` secret (a fine-grained token with Actions: Read and
   write on this repository). Without the token, the daily run picks it up.
   `tpw-recomp`'s `.github/workflows/flatpak.yml` does all this.
2. Add it to `apps.json`: its app ID, name, one-line summary and repository.
