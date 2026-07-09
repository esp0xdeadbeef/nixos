# Contact Intake and SMS Verification

This document describes the concrete `s-gamma` target for the public contact
form, SMS reachability verification, and the first intake portal. SMS is not an
identity or MFA trust anchor here. It is only used to verify that the submitted
phone number is reachable during intake.

## Goals

- Accept contact form submissions from the public web page.
- Verify the submitted phone number with a short-lived SMS code.
- Create a scoped intake thread after phone verification.
- Allow callback during the intake window.
- Avoid duplicate/spam submissions with short retention and rate limits.
- Keep customer data out of logs and out of the Nix store.
- Prepare the model for later tenant workspaces, Samba AD, KMS, and dedicated
  tenant VPS access.

## Non-goals

- Do not use SMS as strong authentication for customer infrastructure.
- Do not create a full customer tenant automatically from a public form.
- Do not grant file upload, decrypt, storage, or tenant-VPS access based only on
  SMS verification.
- Do not use reusable week-long bearer links as the actual credential.

## Flow

```text
public contact form
  -> create pending intake request
  -> send SMS verification code
  -> verify code
  -> create one-time portal bootstrap link
  -> create server-side portal session
  -> open 7-day intake thread
  -> manual qualification before tenant/customer workspace
```

The "account" created by the contact form is an intake account, not a customer
tenant account. It can view its own request and chat in the intake thread. It
does not get access to previous work, tenant data, object storage, KMS decrypt
rights, or customer infrastructure.

## States

```text
pending_phone_verification
phone_verified
intake_open
qualified
converted_to_customer
expired
abuse_blocked
```

Unverified requests expire quickly. Verified requests keep the phone number for
the intake/callback window. If the request becomes a real lead or customer, the
retention purpose changes and must be covered by the privacy notice.

## Retention

```text
unverified request:
  raw phone number: delete within 24-48 hours
  abuse hash: retain short-term if needed

verified intake request:
  raw phone number: retain up to 7 days for callback/intake
  portal thread: retain up to 7 days by default

converted customer:
  contact details may be retained for customer communication,
  administration, and legal obligations
```

Phone numbers should be normalized before use. Store an HMAC of the normalized
number for cooldown and abuse checks. Store the raw number only encrypted, and
only while there is a live purpose for calling or sending SMS.

## Token model

SMS code:

```text
code: 6-8 digits
stored value: HMAC(server_secret, request_id || code)
validity: 10-15 minutes
attempts: max 5
resend: max 3, with cooldown
resend behavior: invalidate previous code
logging: never log the code
```

Portal bootstrap link:

```text
selector: random public id
validator: 256-bit random secret
stored value: hash(validator)
validity: 15-60 minutes
use: one-time
on success: mark used and create server-side session
```

The week-long period belongs to the server-side intake thread/session policy,
not to a reusable magic link.

## Abuse controls

Minimum controls before sending SMS:

```text
per IP:
  submission and SMS-send rate limits

per phone HMAC:
  send cooldown
  daily limit

per request:
  OTP attempt limit
  OTP expiry
  resend limit

per origin:
  CORS/origin allowlist

anti-automation:
  honeypot first
  optional Turnstile/CAPTCHA only after suspicious behavior
```

Do not hard-ban a phone number for a week. Use a cooldown and duplicate intake
handling. A hard ban is easy to abuse as denial-of-service.

## SMS gateway

The app should support an SMS provider abstraction:

```text
dry-run:
  local development and tests

http-json:
  generic provider adapter loaded from SOPS runtime config

future:
  provider-specific adapters if needed
```

Provider credentials and sender configuration belong in SOPS, for example:

```text
contact/intake/env
contact/sms/env
```

No SMS API token, webhook secret, sender name, endpoint, or phone number belongs
in public Nix.

## Storage

Initial implementation can use SQLite on `s-gamma`:

```text
/var/lib/contact-intake/intake.db
```

The database should contain structured tables, not mailbox-only state:

```text
intake_requests
otp_challenges
portal_tokens
portal_sessions
intake_messages
rate_limits
audit_events
```

Fields with personal data should be minimized. Sensitive fields should be
encrypted at application level where practical, or kept behind filesystem and
backup encryption until the KMS/OpenBao layer exists.

## `s-gamma` services

Target NixOS modules:

```text
contact-intake.nix
  contact-intake system user
  systemd service bound to 127.0.0.1
  SOPS environment files
  persistent state directory
  nginx reverse proxy location

mail.nix
  existing Postfix/Dovecot mail delivery

future kms.nix
  OpenBao/KMS integration

future idm.nix
  Samba AD/domain integration
```

The service should be reachable only through nginx. It should not bind to a
public interface directly.

## Privacy notice

Public code is not a privacy notice. The public page must explain:

- which data is collected;
- why SMS verification is used;
- that the phone number may be used for callback during intake;
- unverified and verified retention windows;
- SMS/hosting processors at a high level;
- how to request access, correction, or deletion.

Short form text near submit:

```text
We use your details to verify your request and contact you about your inquiry.
If no customer relationship is established, verified phone numbers are deleted
after the intake window. See the privacy notice.
```

## Upgrade path

Phase 1:

- Add SQLite-backed intake request state.
- Add SMS dry-run and generic HTTP SMS provider adapter.
- Add phone verification endpoint.
- Add one-time portal bootstrap link.
- Add 7-day intake thread.
- Add privacy page.

Phase 2:

- Add KMS/OpenBao for field encryption and tenant keys.
- Add object storage for uploads.
- Add manual customer qualification.
- Add tenant workspace model.

Phase 3:

- Add Samba AD / directory integration.
- Add per-tenant service accounts and groups.
- Add RADIUS/NAC/network intent integration for managed devices.
- Add dedicated tenant VPS workflow.
