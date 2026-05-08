# HODW AQX auth bootstrap

This app now uses Firebase Authentication plus a Firestore `users` collection.

## Login mapping

- Visible username field: **Melco ID**
- Internal Firebase Auth email: `MELCO_ID@hodw.local`
- Example: Melco ID `1015083` -> `1015083@hodw.local`

## Current secure path

The old stuck/manual Firebase Console path is replaced by a **Cloudflare Worker provisioner** kept in:

- `cloudflare-worker/`

That Worker uses a Google service account to:

- create/update Firebase Auth email/password users
- create/update Firestore `/users/{uid}` profile documents
- force `requirePasswordChange: true`
- keep Melco ID as the visible login name

## Important security rule

**Do not put first-admin bootstrap secrets into the public Flutter web build.**

That means:

- first admin bootstrap is **server-side only** through the Worker
- regular login-user creation can happen from the app **after an admin is already signed in**
- the Worker checks the caller's Firebase ID token and Firestore role for `/users`

## One-time first admin bootstrap

Create Ricardo's first admin account through the Worker using:

- Melco ID: `1015083`
- display name: `Ricardo`
- role: `admin`
- temporary password: `Welcome2026`

After that:

1. Ricardo logs in with Melco ID `1015083`
2. The app forces password change immediately
3. Ricardo can create other login users from Settings

## Worker config

Configure these secrets/vars in Cloudflare Worker:

- `GCP_SERVICE_ACCOUNT_JSON` = full contents of the Firebase service account JSON
- `FIREBASE_WEB_API_KEY` = Firebase web API key for project `aqx-dive-log`
- `BOOTSTRAP_TOKEN` = strong random one-time/admin bootstrap token

## Worker endpoints

- `POST /bootstrap-admin`
  - protected by `BOOTSTRAP_TOKEN`
  - for first admin only
- `POST /users`
  - requires Firebase ID token in `Authorization: Bearer ...`
  - caller must already be an admin in Firestore

## In-app behavior

- login still uses Melco ID + password
- first-login password change remains enforced
- Settings now blocks non-admin users from:
  - add/edit/remove divers
  - New Day Reset
  - login-user creation
- admin users can create login users from Settings

## Default password policy

Current default temporary password for newly provisioned users:

- `Welcome2026`

Users must change it on first login.

## Notes

- Plain passwords are not stored in the repo beyond the documented temporary default policy.
- Anonymous auth must remain disabled.
- Do not replace this with a generic local app lock.
- Preserve existing divers/log/checkins data.
