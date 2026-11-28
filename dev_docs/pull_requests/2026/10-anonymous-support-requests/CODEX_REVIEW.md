# PR #10 · Anonymous support requests

| Severity | Finding | Resolution |
| --- | --- | --- |
| High | A connected guest page continued to load new comments after link expiry, an email change, or an admin disabling guest access. | Every refresh checks the setting and token. Losing access clears the page and unsubscribes the socket. Verification and reply writes also check guest ownership under the ticket row lock. |
| High | A bulk update sent every ticket in the batch to each affected account's personal topic, including guest tickets. | Each personal broadcast contains only that account's tickets. The staff topic still receives the whole batch. |
| Medium | A staff reply could send the submitted title and name to an unverified address. | Reply notifications require a verified address and enabled guest access. |
| Medium | Comment broadcasts could reach subscribers before the transaction committed. The staff list also lacked handlers for comment events. | Guest and account replies broadcast after the transaction returns. The staff list ignores comment events because its rows display no comment data. |
| Medium | A limiter failure allowed anonymous requests to proceed. The resend hook also lost the host's submitted verification fields. | Limiter failures return the rate-limited result. The resend hook receives the original fields and normalized email address. |
| Medium | Inline style attributes hid the spam-trap fields, so a restrictive host style policy could leave them visible. | All three forms use the existing Tailwind screen-reader-only class with the fields excluded from keyboard and assistive navigation. |
| Medium | Running the tests with a generic PostgreSQL database selected could migrate that database. | The suite defaults to the package's test database and supports an explicit CUSTOMER_SUPPORT_TEST_DATABASE override. |

## Verification

The PostgreSQL suite covers the V2 schema, mail delivery, token verification, reply handling, public routes, CSP checks and guest LiveViews. Review regressions exercise connected-page expiry and revocation, stale writes, recipient-specific broadcasts and verified-only staff reply mail.

All 118 tests passed with PostgreSQL integration enabled. The final `mix precommit` run passed compilation with warnings treated as errors, dependency checks, formatting, strict Credo and Dialyzer. Browser behavior was exercised through LiveView tests.
