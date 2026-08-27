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

## Large raster assets

`assets/PROVENANCE.json` is the machine-readable inventory for every wallpaper
and every other repository asset currently larger than 1 MiB. It records exact
bytes, dimensions, media type, and the commit that first added the bytes.

The current Git history contains no reliable creator, original source URL, or
redistribution license for those files. All three fields are therefore `null`,
and their rights status is explicitly `unknown-owner-action-required`. The
author of the importing commit is evidence of repository introduction only;
the manifest deliberately does not call that person the creator or rights
holder.

Before claiming that these assets may be redistributed, the owner must do one
of the following for each record:

1. establish the creator/rightsholder, canonical source, and license, retain
   the evidence, fill all three provenance fields, and mark that record's
   `rightsStatus` as `documented`; or
2. replace it with an asset whose redistribution rights are documented; or
3. remove it from the repository and managed wallpaper set.

The same review should cover smaller repository-local artwork and brand assets
before a repository-wide license is announced. `tests/repository-policy.py`
checks that every asset over 1 MiB has a record and that its size and SHA-256
have not drifted; it cannot establish legal rights.
