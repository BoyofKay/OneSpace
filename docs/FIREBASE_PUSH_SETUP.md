# OneSpace — Firebase Push Setup (Android preview)

## Verified activation — November 14, 2026
- Android Preview `0.1.403` contains the validated `google-services.json` configuration.
- Both Android phones registered independently under their respective accounts.
- `ONESPACE_FIREBASE_SERVICE_ACCOUNT_JSON` and `ONESPACE_PUSH_CRON_SECRET` are configured in Edge Function secrets.
- Worker password is stored in Supabase Vault (`onespace_push_worker_secret`).
- Supabase migration `0089` fixes the PostgREST service-role JWT claim compatibility; regression test `0013` passed.
- Live authorized server invocation returned HTTP 200, with 1 notification accepted by Firebase and 0 retries.
- Supabase migration `0090` enabled `onespace-fcm-push-delivery` every minute. **Do not run the setup schedule again.**
- Physical Android lock-screen delivery remains an acceptance test; server acceptance alone is not proof of display on a handset.



**Current product:** Supabase remains the authority for messages, reminders,
privacy and accounts. Firebase delivers a generic lock-screen prompt only.
Android preview application ID: **com.onespace.onespace.preview**.

## Part A — Firebase Console, your Google account
1. In https://console.firebase.google.com create a **separate** Firebase project
   named OneSpace. Google Analytics is optional.
2. Project Settings → General → Your apps → Add Android App.
   Package ID: `com.onespace.onespace.preview`.
   Nickname: `OneSpace Android Preview`.
   The SHA certificate is not required for basic FCM.
3. Download **google-services.json** for this exact Android registration.
   Do not rename it to include (1) or (2).
4. Project Settings → Cloud Messaging: check that the Firebase Cloud Messaging API
   is enabled for the Google Cloud project.

## Part B — GitHub private Android build configuration
The app's build workflow will continue to build without Firebase until the
real JSON is provided. Supply it using a private GitHub Actions secret.

1. On a Windows PC, open PowerShell in the folder containing your downloaded
   `google-services.json`. Encode the file **locally**:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path '.\google-services.json')))
   ```
2. In the private `BoyofKay/OneSpace` GitHub repository go to
   Settings → Secrets and variables → Actions → New repository secret.
3. Name: `ONESPACE_GOOGLE_SERVICES_JSON_BASE64`. Value: paste the base64
   output. Do not paste a Firebase **service account** JSON in GitHub.
4. Save. The next verified preview build will read this secret, validate that
   the Android package matches, install the config only on the CI build runner,
   and enable the Google Services Gradle plugin. It is not committed to Git.

## Part C — Server sending key: Supabase Edge Functions Secrets
1. Firebase console → Project settings → Service accounts →
   Firebase Admin SDK → Generate new private key. Download JSON securely
   and store it in your password manager. The file contains a PRIVATE KEY.
2. In the Supabase project `ugwrpeduzyzrujkizqfo` open
   Edge Functions → Secrets. Add `ONESPACE_FIREBASE_SERVICE_ACCOUNT_JSON`
   with the complete JSON file, represented as a single-line JSON string.
   Do NOT upload the key to GitHub, a chat, or your Android phone.
3. The project's `onespace_push_worker_secret` has already been generated
   directly inside Supabase Vault using 256 bits of cryptographic randomness.
   Do **not** create another random string or call `vault.create_secret` again.
4. In the Supabase **SQL Editor**, run:
   ```sql
   select decrypted_secret
   from vault.decrypted_secrets
   where name = 'onespace_push_worker_secret';
   ```
   Copy the returned secret **only inside your browser**; do not paste it into
   ChatGPT, a GitHub commit, or an Android config file.
5. Go to Supabase → Edge Functions → Secrets. Add a new secret:
   Name: `ONESPACE_PUSH_CRON_SECRET`; Value: the exact clipboard contents.
   Save it and clear the clipboard.
6. The Firebase Admin SDK private-key JSON must remain separately stored in
   `ONESPACE_FIREBASE_SERVICE_ACCOUNT_JSON`. Never include it in a query,
   cron command, or Android build.

## Part D — Activate the scheduled worker, only after C is complete
The connected Supabase administrator can activate the following cron job after
the Edge secret is confirmed. The cron command references Vault at execution
time, **never** embeds the decrypted worker secret in GitHub or SQL source.

```sql
select cron.schedule('onespace-fcm-push-delivery', '* * * * *', $cron$
  select net.http_post(
    url := 'https://ugwrpeduzyzrujkizqfo.supabase.co/functions/v1/onespace-push-delivery',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-onespace-push-secret',
      (select decrypted_secret from vault.decrypted_secrets
       where name='onespace_push_worker_secret' limit 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 15000
  );
$cron$);
```

**Do not activate the job until the Edge Function secret is set.** Once enabled,
the worker polls about once per minute. Recurring reminder generation currently
runs every five minutes, so delivery is best-effort, not exact-to-the-second.

## Part E — Two-phone acceptance
1. Install the newest signed preview over the previous one. DO NOT uninstall
   and DO NOT clear app data.
2. On each phone, sign into that partner's OneSpace account, unlock, and allow
   the Android notification permission. Confirm notifications are not disabled
   in device Settings.
3. Create a shared Reminder due a few minutes into the future.
4. Background (do not force-stop) each app and verify each phone displays a
   **generic** OneSpace notification; tap to open the secure OneSpace
   Notifications center. The recipient must still unlock if the session locked.
5. Test snooze and a second reminder. Confirm there are no duplicate push
   deliveries and partner private reminders don't cross accounts.
6. Sign out explicitly and confirm that device stops receiving private alerts.

## Important limits
- Android only for the first configured preview. iPhone will require an
  independent iOS Firebase registration, APNs key and Xcode integration.
- No order tracking integration, offline exact-time guarantee or Firebase
  authentication is introduced.
- Notifications sent in the foreground appear in the in-app feed; the OS may
  suppress system alert banners for an actively open app.
- Network, battery savings, OS force-stop and denied permissions affect FCM.
- Pushing begins only after the Firebase config, service account and scheduled
  worker secret are ALL installed.
