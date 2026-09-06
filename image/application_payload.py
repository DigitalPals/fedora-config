"""Portable filesystem helpers for the offline application seed."""
import os
from pathlib import Path
import re


def include_applications(kickstart: str, packages: list[str]) -> str:
    """Select apps directly, preserving DNF multilib selectors and user removals.

    Making every app a desktop RPM dependency would let removing Steam also
    remove the desktop. Explicit compose selections install the full defaults
    without coupling later application removals to the graphical session.
    """
    section = re.search(r"(?m)^%packages[^\n]*\n", kickstart)
    if section is None:
        raise ValueError("The image kickstart has no package section")
    offset = section.end()
    return kickstart[:offset] + "\n".join(packages) + "\n" + kickstart[offset:]


def relativize_seed_links(seed: Path, original_home: Path) -> None:
    """Relocate native installers' HOME links without changing system links."""
    for link in seed.rglob("*"):
        if not link.is_symlink():
            continue
        target = os.readlink(link)
        if target.startswith(str(original_home) + "/"):
            target = os.path.relpath(seed / Path(target).relative_to(original_home), link.parent)
            link.unlink()
            link.symlink_to(target)
