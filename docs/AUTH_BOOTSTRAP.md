# HODW AQX auth bootstrap

This app now uses Firebase Authentication plus a Firestore `users` collection.

## Login mapping

- Visible username field: **Melco ID**
- Internal Firebase Auth email: `MELCO_ID@hodw.local`
- Example: Melco ID `1015083` -> `1015083@hodw.local`

## First admin bootstrap

The app is prepared to auto-create the **Firestore user profile** for Ricardo's admin account on first successful login, but it **does not create the Firebase Auth password account itself** from client code.

That means the one-time safe bootstrap step is:

1. Open **Firebase Console** for project `aqx-dive-log`
2. Go to **Authentication -> Users**
3. Click **Add user**
4. Create:
   - Email: `1015083@hodw.local`
   - Password: choose a temporary password and share it securely with Ricardo
5. Ensure **Email/Password** provider is enabled in Authentication -> Sign-in method
6. Deploy Firestore rules from this repo
7. Ricardo logs in from the app with:
   - Melco ID: `1015083`
   - Password: the temporary password
8. On first successful login, the app creates `/users/{uid}` with:
   - `melcoId: 1015083`
   - `role: admin`
   - `requirePasswordChange: true`
9. The app immediately forces a password change before normal access

## Provisioning additional users

For each operator/admin:

1. Create a Firebase Auth email/password user using `MELCO_ID@hodw.local`
2. Create Firestore document `users/{uid}` with at least:

```json
{
  "melcoId": "1234567",
  "role": "operator",
  "requirePasswordChange": true,
  "displayName": "Optional Name"
}
```

Use `role: "admin"` only for admins.

## Notes

- Plain passwords are **not** stored in this repo.
- Anonymous auth must remain disabled for production access.
- Non-admin UI is blocked from roster management and New Day Reset.
- Firestore rules in this repo align with the role model, but New Day Reset is mainly enforced in app UI because it reuses normal writable collections.
