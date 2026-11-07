# obs-sync

Unofficial repackages of upstream release packages for apps without their own
repository, built on the [Open Build Service](https://build.opensuse.org) for
Debian/Ubuntu (deb), Fedora/openSUSE (rpm) and Arch Linux.

**Not affiliated with the upstream projects.** The packages contain the unmodified
prebuilt files of the official upstream `.deb`; they are not built from source.
Report packaging issues here, not upstream.

## Migration to official repositories

If an app gets an official repository, a final update from this project adds that
repository and its signing key (fingerprint taken from upstream's own documentation)
to your system: apt via /etc/apt/sources.list.d/ + /usr/share/keyrings/, dnf via
/etc/yum.repos.d/, zypper via /etc/zypp/repos.d/. Arch users get a notice instead,
because pacman repositories can only be added by editing /etc/pacman.conf.
The app is then removed from this project. Planned migrations are listed here before
they happen.

Planned migrations: none yet.


## How it works

`.github/workflows/obs-sync.yml` runs daily. For every line in `apps.txt` it checks the
newest GitHub release; if it is not in `state/published.txt` yet, it

1. repacks the upstream `.deb` into a Debian source package
   (`scripts/make-source-package.sh`, checksum verified against `SHA256SUMS.txt`
   where upstream provides one),
2. generates `PKG.spec` and `PKGBUILD` from the same payload
   (`scripts/make-obs-recipes.sh`), taking dependencies from the upstream `.rpm` and
   Arch package if the release has them,
3. uploads everything to the OBS package with `osc` and removes the previous version's
   files. OBS then builds and publishes signed repositories.

| Target | Recipe | Dependencies taken from |
|---|---|---|
| Debian / Ubuntu | `.dsc` + `debian.tar.xz` | upstream `.deb` |
| Fedora / openSUSE | `PKG.spec` | upstream `.rpm`, otherwise none |
| Arch Linux | `PKGBUILD` | upstream `.pkg.tar.zst`, otherwise none |

## Setup

1. On build.opensuse.org create a subproject, e.g. `home:JokerGermany:apps`.
2. Repositories → "Add from a Distribution": e.g. Debian 12/13, xUbuntu 24.04/26.04,
   Fedora (current), openSUSE Tumbleweed, Arch Extra. Architecture: x86_64 only.
3. GitHub → Settings → Environments → `obs` (deployment branches: `main` only):
   secrets `OBS_USER`, `OBS_PASSWORD`; variables `OBS_PROJECT`, `DEBFULLNAME`, `DEBEMAIL`.
4. Run the workflow manually with `dry_run` = true, then with `only` = `lightcraft`,
   then without filter.

## Notes

- rpm dependency names come from upstream's (Fedora-style) `.rpm` and may not match
  openSUSE package names.
- Without an upstream `.rpm`/Arch package the rpm/Arch builds have no dependencies.
- openSUSE's rpmlint findings are silenced via `PKG-rpmlintrc`.
- Licenses in `apps.txt` other than LightCraft and SchildiChat Revenge are assumed.
