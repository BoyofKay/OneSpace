# OneSpace confirmation branding — QA hosted Supabase

## Hosted project setting (NOT automatically deployed by a schema migration)
1. Open the **QA Supabase** project `ugwrpeduzyzrujkizqfo`.
2. Authentication → Email Templates → **Confirm signup**.
3. Subject: `Confirm your OneSpace email address`.
4. Paste `supabase/email-templates/confirmation.html` in the message body and save.
5. Verify the QA Supabase Auth URL Configuration includes
   `onespace-preview://auth-callback/` as an allowed redirect URL.
6. Send a fresh QA signup confirmation to a disposable address and verify
   that the branded HTML, logo, correct redirect and OneSpace QA app open.
7. Repeat the template setup for **Production** separately only when approved;
   Production's allowed callback is `onespace://auth-callback/`.

Never change the authentication sender/from address back to Supabase branding.
Custom SMTP determines the sender; this file determines email body/subject.
**A GitHub commit is NOT evidence that a hosted Supabase template is live.**

The image URL must be confirmed accessible in a normal email client.
Do not claim the app's email is branded until a delivered email proves it.
