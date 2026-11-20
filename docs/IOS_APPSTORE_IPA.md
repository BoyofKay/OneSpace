# OneSpace iOS — produce a signed IPA for App Store Connect

Status on 2026-11-20: the QA and Production iOS **unsigned** compile artifacts are
available (successful dual build on 2026-11-18), but **cannot be uploaded** to Apple.
`.github/workflows/ios-appstore-ipa.yml` prepares a production-signed, manual
downloadable `.ipa`; it does not upload or release the app.

## What the pipeline will build

- Name: **OneSpace**
- Platform: iOS (iPhone and iPad target); minimum iOS 15.0
- Bundle identifier: **`com.onespace.onespace`**
- Backend: **Production** only (`ONESPACE_ENV=production`), never QA
- Firebase: the matching production iOS `GoogleService-Info.plist`
- Distribution: **App Store** signing and a release `.ipa` in a GitHub Actions
  artifact, valid for TestFlight and App Store Connect submission once Apple accepts it
- Each manual run chooses the app version and uses a new build number
- No uploads to Apple, publication, push delivery or database changes are performed

## Prerequisites in Apple

1. Active Apple Developer Program membership with access to Certificates, IDs & Profiles.
2. An explicit iOS App ID **`com.onespace.onespace`**. Enable Push Notifications.
3. An **Apple Distribution** certificate (not a development certificate). Export as
   `.p12` **with its private key** and set a strong export password.
4. An **App Store Connect distribution provisioning profile** for that exact App ID,
   team and certificate. It must include the production `aps-environment` entitlement.
   Download the `.mobileprovision` file.
5. Add the iOS app `com.onespace.onespace` to the intended production Firebase
   project and download its `GoogleService-Info.plist`.
6. Create the matching OneSpace app record in App Store Connect to receive the build.

Apple certificate/profile creation needs an Apple account, but the build runs on
GitHub's hosted Mac — no personal Mac is needed to run this workflow.

## GitHub Actions secrets (private repository)

Set these at **GitHub → BoyofKay/OneSpace → Settings → Secrets and variables →
Actions → New repository secret**.

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | The Apple Developer team ID (10 characters) |
| `IOS_APPSTORE_CERT_P12_BASE64` | Base64 of the distribution certificate **.p12 including private key** |
| `IOS_APPSTORE_CERT_P12_PASSWORD` | The export password of that .p12 |
| `IOS_APPSTORE_PROFILE_BASE64` | Base64 of the App Store distribution `.mobileprovision` |
| `IOS_GOOGLE_SERVICE_INFO_PLIST` | Base64 of the production iOS `GoogleService-Info.plist` |

On Windows PowerShell, copy a file's base64 to the clipboard (change the path
and repeat for the three files):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\file.p12")) | Set-Clipboard
```

Never commit signing certificates, provisioning profiles, Firebase service files
or private keys to the repository; never paste private keys or passwords into chat.
`ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` are App Store Connect API
credentials for **upload automation** and do not, by themselves, replace the
distribution certificate, private key and provisioning profile required by this
manual-signing workflow.

## Run and download

1. Merge the workflow pull request into `main`. GitHub only exposes new manual
   workflow-dispatch jobs in the repository's Actions tab after they are on the
   default branch.
2. Navigate to **Actions → Build OneSpace iOS signed App Store IPA → Run workflow**.
   Select the current production code branch and enter `app_version` (e.g. `0.1.0`).
3. Once the job succeeds, open the workflow run's **Artifacts** and download
   `OneSpace-iOS-AppStore-signed-<run number>`. Unzip the GitHub artifact ZIP
   to obtain the **`.ipa`**. The artifact is retained for 14 days.
4. Upload the **`.ipa`** through Apple's Transporter app on macOS or Xcode, or
   arrange a separate authenticated CI upload. App Store Connect's app-detail web
   form is not a general-purpose drag-and-drop IPA uploader.
5. When Apple finishes processing it, select the build under TestFlight or prepare
   the App Store submission. Store metadata, privacy disclosures, screenshots,
   Apple Sign in compliance and review approval remain separate release gates.

## Safety checks in the workflow

The job **fails without an artifact** if any of the five credentials is missing,
if the Firebase bundle ID is not `com.onespace.onespace`, if the provisioning
profile targets the wrong team/app or lacks production APNs, if signed IPA
verification fails, or if the output bundle ID is not production.

It modifies signing settings **only in the temporary CI checkout**, not on
`main`. It does not reuse QA identifiers, does not upload to Apple, and does not
change the Android production signing or OneSpace databases.

The actual signed export is **not yet tested** because Apple distribution signing
credentials have not been verified/configured through this session. A successful
unsigned compile is not proof of a valid signed IPA.
