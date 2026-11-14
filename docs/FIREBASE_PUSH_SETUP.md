# OneSpace — Firebase Push Setup (Android preview)

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
3. Choose a long random worker secret in your password manager.
   Add `ONESPACE_PUSH_CRON_SECRET` to Supabase Edge Functions Secrets
   with that random value.
4. Do not configure Firebase credentials in the Android APK or in Dart
   definitions. They stay server-only. The deployed `onespace-push-delivery`
   Edge Function uses Firebase HTTP v1 and OAuth2.

## Part D — Activate the scheduled worker, only after C is complete
Supabase SQL Editor: execute the following **with YOUR randomly generated
worker secret** (matching the value in Edge Function Secrets above).
The query stores the secret in Supabase Vault. Do not expose that value to
app users or commit it to GitHub.

```sql
select vault.create_secret('PASTE_YOUR_RANDOM_WORKER_SECRET',
                           'onespace_push_worker_secret');

select cron.schedule('onespace-fcm-push-delivery', '* * * * *', $$
  select net.http_post(
    url := 'https://ugwrpeduzyzrujkizqfo.supabase.co/functions/v1/onespace-push-delivery',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-onespace-push-secret',
      (select decrypted_secret from vault.decrypted_secrets
       where name='onespace_push_worker_secret' limit 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 15000
  );
$$);
```

Do not re-run the `create_secret` operation repeatedly; use Vault's update
facilities to rotate the value and update the Edge Functions Secret together.
The schedule is one minute; reminder generation is currently five-minute cron,
so delivery time is best-effort, not exact-to-the-second.

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
