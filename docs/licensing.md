# Licensing and asset provenance

There is currently no repository-root `LICENSE` or `COPYING` file. Repository
visibility and a Git commit history do not themselves grant permission to copy,
modify, or redistribute the original configuration code. This document records
that boundary; it does not choose a software license on the owner's behalf.

## Repository code and configuration

The owner must choose the intended terms, confirm that every contributor can
license their contribution on those terms, and add the corresponding canonical
license text at the repository root. If different directories need different
terms, add unambiguous per-directory notices and a root summary. Until then,
downstream users should not infer an open-source license.

Files copied or downloaded from other projects remain under their upstream
terms. In particular:

- pinned single-file fonts install their verified upstream license text beside
  the font;
- the OPPO Sans archive supplies its own font license agreement, which the role
  preserves beside the installation;
- the Cybex role checks out a pinned upstream artwork revision and then overlays
  repository-local theme files; and
- product names, logos, and brand SVGs may also be subject to trademark rules,
  independently of any software license eventually selected here.

A repository-wide software license must not be presented as relicensing those
third-party materials.

## Repository assets

The undocumented screenshot, avatar, and wallpaper collection previously in
the repository have been removed. A public installation starts without a
bundled wallpaper and lets the user select their own directory.

`assets/PROVENANCE.json` remains the machine-readable gate for every
repository-distributed asset larger than 1 MiB. It is currently empty, and
`tests/repository-policy.py` fails if a new large asset appears without a
matching provenance record. Smaller brand artwork and third-party downloads
remain covered by `assets/THIRD_PARTY_LICENSES.md`, their upstream notices, and
the dependency policy. This technical check cannot establish legal rights;
new redistributed artwork still needs a creator, source, and compatible
license recorded before publication.
