# Quickshell icon assets

The shell chooses icons by semantic role:

- Generic actions and status use `Common/Sym.qml` and Material Symbols
  Rounded.
- Product identities use `Common/BrandIcon.qml` and the allow-list in
  `Common/BrandIcons.qml`.
- Installed applications use the desktop icon theme through
  `Quickshell.iconPath()`; tray items retain the status-notifier icon supplied
  by their application.
- Small animated primitives may be drawn in QML when an icon-font shape does
  not animate or align correctly.

Do not add a product SVG directly to a view. Add one canonical asset here,
record its provenance below, register it in `BrandIcons`, and render it through
`BrandIcon`. Contextual monochrome states are runtime tints, not duplicate
`-white` or `-dim` files.

## Provenance

The source revisions are pinned so each path can be audited independently of
later upstream changes. Local changes are limited to adding a shell palette
fill, removing redundant SVG metadata, or cropping a mark out of its app-icon
background.

| Assets | Vector source | Revision | Local treatment |
| --- | --- | --- | --- |
| `claude.svg`, `github.svg`, `kimi.svg`, `tailscale.svg`, `whatsapp.svg`, `youtube.svg` | [Simple Icons](https://github.com/simple-icons/simple-icons) | `4a79bb55697c85b8bc9f3caa22be747e0277ad4f` | Upstream path with a product/shell palette fill. |
| `openai.svg` | [Tabler Icons: `brand-openai`](https://github.com/tabler/tabler-icons/blob/5a0fe38e97784d94279ce4eb1bf85f9a91bf027e/icons/outline/brand-openai.svg) | `5a0fe38e97784d94279ce4eb1bf85f9a91bf027e` | Upstream strokes with the shell's Codex colour. |
| `t3.svg` | [T3 Code production logo](https://github.com/pingdotgg/t3code/blob/a3a8cbd60539b4af4de8f96c892dbd07a2b6c041/assets/prod/logo.svg) | `a3a8cbd60539b4af4de8f96c892dbd07a2b6c041` | Cropped to the wordmark; background removed. |

Simple Icons is distributed under CC0 1.0. Tabler Icons and T3 Code are MIT
licensed; their notices are retained in `THIRD_PARTY_LICENSES.md`. Product
names and logos remain trademarks of their respective owners regardless of
the vector files' copyright licences.
