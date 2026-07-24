# Move-only mail classifier

This profile classifies hosted IMAP inboxes through a declaratively selected
Ollama model. It is designed as a reconciliation service: mailbox-set secrets
are discovered by the host configuration, and every hosted client account is
processed without adding per-domain code.

## Safety boundary

The service may:

- list and select private and same-domain shared inboxes;
- fetch messages with `BODY.PEEK[]`, without marking them read;
- create and subscribe fixed destination mailboxes;
- append internal feedback and reply messages with the `\Draft` flag;
- move a message atomically with `UID MOVE`.

It may not copy, delete, expunge, set `\Deleted`, or fall back to a
copy-and-delete sequence. It also has no SMTP transport and cannot send a
draft. Before Python starts, the runner removes every `MAIL_ACCOUNT_*` and
`MAILBOX_*` variable, including any unrelated SMTP settings, and exports only
the minimum IMAP connection fields. The system closure depends on a static
Python AST validation which rejects `COPY`, `DELETE`, `EXPUNGE`, `STORE`, SMTP
imports and send methods, dynamic UID commands, and any UID command other than
`SEARCH`, `FETCH`, or `MOVE`. The VM therefore fails to build if either the
move-only or no-send boundary is crossed.

`Junk` is an ordinary destination mailbox. It is never treated as a retention
or deletion queue.

The client requests capabilities again after login because Dovecot exposes
mailbox commands such as `MOVE` only in its authenticated capability set.
Missing or failed post-login capability discovery aborts the run before mailbox
selection; the code never guesses that MOVE support is present.

## Feedback and reply drafts

Every active classification creates an internal message under
`Drafts/Classifier Feedback` containing the fixed label, confidence and a
short Dutch reason. For legitimate human correspondence that benefits from a
response, Ollama may additionally create a clean, ready-to-review reply under
`Drafts/Classifier Replies`. Junk, newsletters, receipts and automated
notifications never receive reply drafts. That exclusion is enforced after the
model response as well, so an incorrect `reply_recommended` value cannot bypass
it.

Feedback is addressed from and to the mailbox itself and marked
`Auto-Submitted`; reply drafts are addressed to the parsed `Reply-To` or
`From` address but are only appended through IMAP. Both carry `\Draft` and
`\Seen`. A deterministic per-source-UID fingerprint is searched before append,
so an interrupted run can finish its MOVE without creating duplicate drafts.
The original source is reselected after draft work and only then moved with
`UID MOVE`.

Reasons and proposed reply bodies stay inside the mailbox. The journal records
only generic ids, label, confidence and whether a draft was created; it never
records message content, reason text or the proposed reply.

Only private `INBOX` and direct shared mailbox roots are sources. Messages in
`Junk`, `Sorted/*`, `Drafts/*`, and other nested folders are never
reclassified. Feedback is created for new classifications; already-sorted
messages are deliberately not backfilled.

IMAP list operations use a literal empty reference name and quote both mailbox
names and wildcard patterns. This is significant with Python `imaplib`: a
Python empty string omits the reference argument, and an unquoted wildcard is
not a valid Dovecot list pattern.

## Discovery and scheduling

The runner reads protected mailbox-set profiles on every invocation. It
processes only accounts declared both server-side and client-facing, which
prevents duplicate traversal by every shared mailbox owner. A mailbox set added
through the normal secret-and-rebuild workflow is included automatically when
the host sets `local.mail.mailboxSets.names = null`.

The default timer schedule is once per minute. Runs cannot overlap because the
classifier is a single systemd oneshot service. Missing secrets fail the
current run immediately so a later timer invocation can retry; they cannot
leave an indefinitely blocked service behind.

Each account verifies the exact Ollama model before opening IMAP. If Ollama
becomes unreachable after that probe, the current account stops after the first
failed request instead of retrying every message. No MOVE is attempted for that
message, and the next timer run starts again from the still-present source UID.

## Rollout

Keep `dryRun = true` and the timer disabled for the initial single-mailbox
trial. A dry run uses read-only IMAP selections, records no message content or
identity-bearing headers in the journal, and logs only generic account ids,
fixed labels, confidence, and hashed mailbox ids.

After reviewing the complete private and shared trial, set `dryRun = false` and
enable the timer. The Ollama base URL and exact model name remain explicit Nix
options; service startup fails closed when that model is not installed.
