# T3 composer manual verification

Use a connected T3 Code server with at least one provider that advertises a
select trait and a boolean trait.

## Disclosure and layout

- [ ] Open an existing thread and confirm `Run settings` starts collapsed and
  leaves more height for the conversation.
- [ ] Open New Thread and confirm `Run settings` starts expanded.
- [ ] Toggle the disclosure, leave the page, reopen it, and confirm it resets to
  that page type's default instead of persisting the previous choice.
- [ ] Confirm the collapsed header has a right-pointing chevron; the expanded
  header has a downward chevron and a subtle divider above its fields.
- [ ] Confirm the collapsed state shows separate chips for provider/model
  (with the provider glyph), reasoning level, and interaction mode, and that
  tapping any chip expands the disclosure.
- [ ] Confirm access remains visible as a chip outside the disclosure body,
  `Full access` is amber there and in the expanded Access picker.
- [ ] At 460 px popover width, confirm controls use two columns. At 280 px,
  confirm they stack without horizontal clipping. On a short screen, confirm the
  popover stays bounded and its existing scroll areas remain usable.

## Input and state

- [ ] Toggle the whole header with the mouse, then use `Tab`, `Enter`, and
  `Space`; confirm keyboard focus has a visible ring and the chevron follows the
  state.
- [ ] Repeat while the composer is read-only, running, or sending; the header
  must still open for inspection while each setting remains disabled.
- [ ] Tab through provider, model, access, mode, select traits, boolean traits,
  prompt, and Send. Exercise picker open/close, arrow-key selection, and
  `Escape`.
- [ ] Open every picker in both New Thread and an existing thread. Confirm its
  menu is opaque and stays above the other settings, prompt, buttons, and error
  text; opening a second picker must close the first. Reopen it and click
  elsewhere in the popout without selecting an option; the menu must close and
  the underlying control must still receive that click.
- [ ] Test idle, running, read-only, sending, plan-ready, and provider-locked
  threads. Confirm the prior enablement, model-locking, prompt, and send behavior
  is unchanged.
- [ ] Change provider/model and confirm the traits and summary chips update.
  Confirm Mode only appears when supported, and exercise every advertised
  select and boolean trait.
- [ ] Select Ultrathink and confirm prompt injection and the prompt highlight
  still work. Trigger a trait validation error, collapse the disclosure, and
  confirm the error remains visible.

## Automated and runtime checks

- [ ] Run `node --test roles/desktop/files/quickshell/Common/tests/t3code-helpers.test.cjs`.
- [ ] Reload `quickshell.service` and inspect that invocation's journal for QML
  load failures, syntax errors, binding loops, invalid sizing, and oversized
  buffers.
