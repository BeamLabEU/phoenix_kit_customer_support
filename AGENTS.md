# AGENTS.md

## Content-Security-Policy

The module works under a host policy that allows inline code by nonce only
(`script-src 'self' 'nonce-…'`); core's guide is `guides/content-security-policy.md`.
It renders no inline `<script>` / `<style>` and no inline event handler, and ships
no JavaScript of its own.

- No inline event handlers (`onclick=`, `onerror=` …): no nonce covers an
  attribute. Use a `phx-` binding or `Phoenix.LiveView.JS`.
- A new inline `<style>` / `<script>` carries the page's nonce. Core's
  `PhoenixKitWeb.CSP.nonce/1` is newer than this module's core floor, so read it
  through a feature-detecting helper (`Code.ensure_loaded?/1` +
  `function_exported?/3` + `apply/3`, answering `nil` on an older core) in
  `lib/phoenix_kit_customer_support/web/csp.ex`, added with its first caller
  (model: `phoenix_kit_hello_world`). Never raise the core floor for it, and never
  put a nonce into a cached body or an e-mail.
- If the module starts shipping JavaScript (`js_sources/0`), list the bundle in
  `@bundles` of the test below, and stamp any `<style>` / `<script>` it creates
  with `PhoenixKitInternals.adoptStyle` before insertion.
- `test/csp_inline_tags_test.exs` guards the above.
