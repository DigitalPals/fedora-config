# Hermes menubar client

The Quickshell Hermes widget is a native remote-only conversation client backed
by the lightweight local `hermes-menubar-bridge.service`. Hermes Agent itself
is not installed or run on this workstation. The dropdown lists the remote
WebUI's existing conversations directly. Opening the widget starts on **New
chat**; choosing a historical conversation loads its transcript, and sending
the first message in New chat creates a normal WebUI session.

## Remote sign-in

The remote origin is intentionally not tracked in inventory or embedded in the
systemd unit. Enter it in the widget on first sign-in; the bridge then keeps the
origin and its session cookies together in its private state file. The widget
probes the public `/api/auth/status` endpoint and only reports **Connected**
after Hermes confirms an authenticated session.

When sign-in is required, open the Hermes popover and enter:

- **URL:** the configured Hermes WebUI origin, including its port
- **Password:** the password configured on that Hermes WebUI

The password is used for one `POST /api/auth/login` request, cleared from the
field immediately, and not retained by the bridge after that request. It is
never written to inventory, a systemd environment, or the conversation cache.
The resulting origin-bound cookie is stored at
`~/.local/state/hermes-menubar/remote-webui-auth.json` with mode `0600`.

An HTTP 302 pointing to `/login` means that there is no valid WebUI session; it
must not be treated as agent connectivity. Expired cookies return the widget to
the URL-and-password form automatically.

## Activity and streaming

Conversation history comes from `GET /api/sessions` and `GET /api/session`.
The detail request uses WebUI's `msg_limit`/`msg_before` window contract, loads
80 visible rows at a time, and keeps at most 250 renderable messages in the QML
model. **Load earlier history** retrieves preceding windows without making a
large tool-heavy session cross the loopback bridge in one response.

History is projected at an explicit presentation boundary. Only non-empty
user, assistant, and system prose becomes a message bubble. `role: tool`,
`session_meta`, empty assistant tool-call carriers, and other protocol records
never fall through to assistant Markdown. OpenAI `tool_calls`, Anthropic
`tool_use`/`tool_result` blocks, and session-level tool summaries are joined by
their call ID, but they do not accumulate as transcript rows. While a turn is
active, one compact activity line follows the newest tool name, short detail,
and status in place; it disappears when the turn settles. Structured text,
image markers, and file markers are normalized without serializing arbitrary
content objects into chat.

Prompts use `POST /api/chat/start`, with the response consumed from Hermes'
authenticated server-sent-event stream. The bar and conversation view
translate those events into useful live states, including working, thinking,
tool use, context compression, waiting for approval or clarification,
interrupted, failed, and done. Reasoning, warnings, goals, todos, context usage,
token metering, and unconsumed steering are retained as compact session state
instead of synthetic transcript messages. The view docks their summary to the
composer; reasoning detail can be expanded there without adding a second
transcript header. Long settled messages start collapsed and can be expanded
in place. Stream reconnects resume with the last event ID and reconcile against
Hermes' session and stream-status endpoints.

The composer discovers provider/model choices from `GET /api/models` and the
selected model's reasoning controls from `GET /api/reasoning`. Model changes on
an existing conversation use `POST /api/session/update`; new sessions and chat
starts carry the explicit model/provider choice. Reasoning effort changes use
`POST /api/reasoning`. Catalog and reasoning responses are bounded and
sanitized by the loopback bridge before QML receives them, and the controls
disappear or disable themselves when the WebUI does not advertise usable
choices.

After authentication the bridge reads the WebUI gateway-stream capability
probe and publishes the negotiated contract to QML. It also supervises the
always-on `/api/sessions/events` list-invalidation stream and the selected
conversation's `/api/session/stream` channel. These recover conversations
created by another client, background-task completions, and server-initiated
turns without polling or replaying a prompt. Older WebUI versions degrade to
manual/list refresh when a stream endpoint is genuinely unavailable. Features
without an upstream capability signal—attachments, branching, message editing,
and regeneration—remain disabled rather than being guessed. Model selection
and reasoning effort are enabled only after their discovery endpoints return a
usable contract.

The small Python bridge remains loopback-only on `ws://127.0.0.1:9120/ws`. It
owns the remote cookie and never exposes it to QML; it does not contain or run
the Hermes Agent model/runtime. Browser-originated turns are owned by the
remote Hermes Gateway rather than imported into the long-running WebUI Python
process. Updating the Agent checkout therefore cannot stale the WebUI process
used by this widget.

## Diagnostics

```bash
systemctl --user status hermes-menubar-bridge.service
journalctl --user -u hermes-menubar-bridge.service -b --no-pager
curl -fsS "${HERMES_WEBUI_ORIGIN%/}/api/auth/status" | jq
```

The public status request should be reachable even while signed out. A healthy
password-protected server reports `auth_enabled: true`,
`password_auth_enabled: true`, and `logged_in: false` until the widget has a
valid cookie.

The remote WebUI must keep gateway-backed chat enabled. On the WebUI host,
check the non-secret settings that Hermes hot-reloads from its configuration:

```bash
hermes config get webui_chat_backend
hermes config get webui_gateway_base_url
hermes config get webui_gateway_use_runs_api
```

The expected values are `gateway`, the existing private Gateway API origin,
and `true`. The WebUI reuses its existing `API_SERVER_KEY` internally; never put
that credential in this repository or in the menubar bridge. A new
`agent_runtime_stale` response means the remote WebUI has fallen back to its
legacy in-process chat backend and should be treated as a routing-configuration
regression, not as a reason to restart WebUI after every Agent update.
