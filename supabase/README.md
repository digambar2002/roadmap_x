# RoadmapX sync backend

The schema in [`schema.sql`](schema.sql) is already applied to the live
project. Re-running it is safe — every statement is idempotent, and it has been
verified by applying it twice in a row.

## Credentials

`SUPABASE_URL` and `SUPABASE_ANON_KEY` reach the app as build-time defines. The
real values live in `dart_defines.json` at the repository root, which is
**gitignored**: this repository is public, and while the anon key grants nothing
on its own (RLS is what protects the data), publishing it invites strangers to
burn the project's free-tier signup and email quota. Copy
`dart_defines.example.json` to `dart_defines.json` on a new machine.

```sh
flutter run   --dart-define-from-file=dart_defines.json
flutter build apk --release --dart-define-from-file=dart_defines.json
```

In VS Code, pick **RoadmapX (sync enabled)** from the run menu —
[`.vscode/launch.json`](../.vscode/launch.json) passes the file for you.

Without the defines the app still builds and runs; it stays local-only and the
Premium screen reports that sync is unavailable.

## Before you ship: turn off email confirmation

The project currently has **Confirm email ON** with Supabase's built-in SMTP,
which is rate limited to a handful of messages per hour and is meant for
development only. Testing hit that limit immediately
(`over_email_send_rate_limit`), and real users would hit it too — they would
create an account and then never receive the confirmation mail.

Two ways out, and for this product the first is better:

1. **Authentication → Sign In / Providers → Email → turn off "Confirm email".**
   Verification buys little here: an account is worthless until you activate it
   by hand, and you are already exchanging email with the user to do that.
2. Configure custom SMTP (Resend, SendGrid, Postmark) under **Project Settings
   → Authentication → SMTP Settings**, if you want verified addresses.

## Activating a paying user

1. They tap **Settings → Sync → Premium**, create an account, and send you the
   account email shown on that screen.
2. Once they have paid: **Table Editor → `profiles`** → find the row by `email`
   → set `is_premium` to `true`. Optionally set `premium_until` to the end of
   the billing period and note who they are in `note`.
3. Their app picks it up on the next foreground, or immediately if they tap
   "I have paid — check again". Nothing to deploy, no admin site to maintain.

To revoke, set `is_premium` back to `false`. The policies read it live, so
access stops on the next request. Their local data is untouched and the app
keeps working offline.

## What the gate actually enforces

Verified end to end against this project, with two throwaway accounts:

| Check | Result |
| --- | --- |
| Signup trigger creates a `profiles` row | pass |
| New accounts default to not premium | pass |
| Unactivated account cannot write | pass — HTTP 403 |
| Activated account can write | pass — HTTP 201 |
| Activated account reads its own rows | pass |
| A different activated account sees nothing | pass |
| Revoking `is_premium` cuts reads off immediately | pass |
| An elapsed `premium_until` counts as lapsed | pass |
| Clients cannot hard-delete rows (tombstones survive) | pass |

The important consequence: entitlement is enforced by Postgres, not by the
client. A patched build that forces the premium flag locally still receives
nothing, because every policy on `records` calls `public.is_premium()`.

## Checking on a user

```sql
-- Who is active?
select email, is_premium, premium_until, note, created_at
from profiles
where is_premium
order by created_at desc;

-- How much is one account storing?
select collection, count(*), max(server_updated_at) as last_write
from records
where user_id = (select id from profiles where email = 'them@example.com')
group by collection;
```

## Schema notes

`public` holds exactly two tables:

- **`profiles`** — one row per account plus the manually flipped premium
  switch. Readable by its owner, writable only by the service role, so a client
  cannot promote itself.
- **`records`** — every synced row from every collection, as `jsonb`. One
  generic table rather than one per model, so adding a field to a Dart model
  needs no migration here, one set of policies covers everything, and one
  realtime subscription carries all collections.

Earlier experimental tables (`goals`, `milestones`, `tasks`, `roadmap_items`)
were dropped along with their triggers and the `touch_updated_at` function.
`auth.schema_migrations` and `realtime.schema_migrations` are Supabase's own
internals and were left alone.
