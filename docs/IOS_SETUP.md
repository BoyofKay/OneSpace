# OneSpace on iPhone — what is ready and what Ahmed needs to do

## Ready in the code (R63)
- The same Flutter app, with native iPhone code for everything Android does:
  - Voice commands with live words, using Apple speech recognition (on-device when the iPhone supports it, otherwise Apple's servers), spoken replies and Arabic.
  - Long-press the app icon → **Voice command**.
  - Travel documents picker; **Download my data** and scrapbook PNG through the iPhone share sheet ("Save to Files" / "Save Image").
  - Pick a contact from Contacts; **Add to Contacts** opens Apple's new-contact screen (you confirm there).
- Permission texts for microphone, speech, camera, photos, Face ID and contacts. Portrait only.
- iPhone app icons from the new logo.
- Push: the app registers iPhones as `ios` devices, and the push worker sends iPhone sound and grouping settings. Push works as soon as the Firebase and APNs steps below are done.
- GitHub workflow **Build OneSpace for iPhone (unsigned)** compiles the app on a Mac on every change to `ios/`. It proves the code builds but cannot be installed: Apple requires signing.

## Not on iPhone yet
- **Share to OneSpace from other apps.** iOS needs a separate Share Extension with an App Group, which needs your Apple account to create. Planned after the first TestFlight build.
- Home-screen widgets. These are not on Android either.

## Ahmed's checklist (in order)
1. **Apple Developer Program** — enroll at developer.apple.com/programs ($99/year). Use an individual account, or an organization account if you'll publish under a company (that one needs a D-U-N-S number and takes longer).
2. **App ID**:
   - Certificates, IDs & Profiles → Identifiers → **+** → App ID `com.onespace.onespace`.
   - Enable **Push Notifications**.
   - (Later, for sharing into the app: App Groups `group.com.onespace.onespace`.)
3. **APNs key**:
   - Keys → **+** → name it "OneSpace push" and tick **Apple Push Notifications service** → download the `.p8` file. You can only download it once, so keep it safe.
   - Note the **Key ID** and your **Team ID** (top right of the developer site).
4. **Firebase** (the same project Android uses):
   - Project settings → **Add app → iOS**, bundle ID `com.onespace.onespace` → download `GoogleService-Info.plist`.
   - Project settings → **Cloud Messaging** → Apple app configuration → upload the `.p8` with its Key ID and Team ID.
5. **GoogleService-Info.plist to GitHub**:
   - Base64-encode it (`base64 -i GoogleService-Info.plist | pbcopy` on a Mac).
   - Add the result as the repository secret **IOS_GOOGLE_SERVICE_INFO_PLIST**.
   - Or send me the file and I'll tell you exactly where to paste it.
6. **App Store Connect**:
   - My Apps → **+** New App → iOS, name "OneSpace", bundle ID `com.onespace.onespace`, SKU `onespace`.
   - This is needed for TestFlight, even if you never publish publicly.
7. **Signing for automatic TestFlight builds**: in App Store Connect → Users and Access → Integrations → **App Store Connect API**, create a key (role: App Manager). Add these repository secrets:
   - `ASC_KEY_ID`
   - `ASC_ISSUER_ID`
   - `ASC_KEY_P8` (the `.p8` content, base64)
   - `APPLE_TEAM_ID`

   With those in place I'll add a workflow that signs the app and uploads every iOS build to TestFlight. Kandice then installs it from the **TestFlight** app with an invite to her Apple ID email.

   No Mac is needed on your side.
8. **TestFlight testers**: App Store Connect → TestFlight → Internal Testing → add yourself and Kandice. Up to 100 internal testers are allowed, and they need no Apple review.

## Data and privacy notes for the App Store later
- Speech is handled by Apple's speech recognition. OneSpace never stores audio from voice commands.
- Contacts are only read when you pick one, and only that one contact.
- An App Privacy questionnaire (App Store Connect) will be needed before any public release, not for TestFlight.
