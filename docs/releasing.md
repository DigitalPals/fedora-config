# Publishing Fedora Config releases

Public updates are built from semantic-version Git tags by
`.github/workflows/release.yml`. The workflow will not publish unless the full
source contract and a twice-converged generic Fedora VM both pass.

## One-time repository setup

1. Enable immutable releases in the GitHub repository settings.
2. Keep Actions permitted to create attestations and write release contents;
   the workflow grants only those job-level permissions.
3. Protect the default branch and require the source and generic-VM checks.

The updater refuses a release when GitHub reports `immutable: false`, even if
the archive checksum is otherwise correct.

## Release checklist

1. Review `release-manifest.json`, `VERSION`, the Fedora release,
   configuration schema, minimum updater version, and all dependency pins.
2. Run `./tests/run` and `./tests/fedora-vm-convergence` locally when practical.
3. Commit the intended source and create a signed semantic-version tag, such
   as `git tag -s v1.0.0 -m 'Fedora Config 1.0.0'`.
4. Push the commit and tag. A version containing a hyphen, such as
   `v1.1.0-beta.1`, is published as a prerelease for the beta channel.
5. Wait for the workflow to build, attest, upload, publish, and confirm the
   immutable release before announcing it.
6. On a clean supported machine, run `fedora-config update --check --json`,
   apply the release, and run `fedora-config verify --system`.

Do not edit an existing release. Immutability makes correction explicit: fix
forward, increment the version, and publish a new tag. If rollout must stop,
remove the bad release from channel discovery and publish a corrected release;
users whose system apply failed remain on their previous active source and
retain their prior configuration automatically.

## What the workflow publishes

The release contains a versioned source archive and `SHA256SUMS`. The archive
is reconstructed from the tagged Git tree, its `VERSION` and manifest version
are set to the tag, its installer is checked, and Ansible syntax is validated.
GitHub attestation plus immutable-release verification form the updater trust
boundary; files copied from an arbitrary branch or mutable URL are not
accepted as updates.
