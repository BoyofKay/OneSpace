"""Repository-only iOS checks; no Apple account or macOS runner required."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "ios/Runner"
EXTENSION = ROOT / "ios/ShareExtension"


class IOSProjectTests(unittest.TestCase):
    def test_apple_app_group_entitlements_match(self):
        def plist(path):
            with path.open("rb") as stream:
                return plistlib.load(stream)
        main = plist(RUNNER / "Info.plist")
        extension = plist(EXTENSION / "Info.plist")
        main_entitlements = plist(RUNNER / "Runner.entitlements")
        share_entitlements = plist(EXTENSION / "ShareExtension.entitlements")
        group = "$(ONESPACE_SHARE_GROUP)"
        self.assertEqual(main["OneSpaceShareGroup"], group)
        self.assertEqual(extension["OneSpaceShareGroup"], group)
        for ent in (main_entitlements, share_entitlements):
            self.assertEqual(ent["com.apple.security.application-groups"], [group])
        self.assertEqual(extension["NSExtension"]["NSExtensionPointIdentifier"],
                         "com.apple.share-services")

    def test_invitation_universal_links_entitlement(self):
        with (RUNNER / "Runner.entitlements").open("rb") as stream:
            ent = plistlib.load(stream)
        # onespace.live/app-invite/ (Production) and /qa-invite/ (QA) open the
        # installed app once the website publishes apple-app-site-association.
        self.assertEqual(ent["com.apple.developer.associated-domains"],
                         ["applinks:onespace.live"])

    def test_xcode_share_target_and_flutter_receiver_connected(self):
        project = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text()
        self.assertIn("OneSpaceShare.appex in Embed App Extensions", project)
        self.assertIn('"com.apple.product-type.app-extension"', project)
        self.assertIn("OneSpaceShareInbox.swift in Sources", project)
        self.assertIn('PRODUCT_BUNDLE_IDENTIFIER = "$(ONESPACE_IOS_BUNDLE_ID).ShareExtension";', project)
        self.assertEqual(project.count(
            'PROVISIONING_PROFILE_SPECIFIER = "$(ONESPACE_SHARE_EXTENSION_PROFILE)";'), 3)
        self.assertIn("OneSpaceShareInbox.takeNext()",
                      (RUNNER / "AppDelegate.swift").read_text())
        self.assertIn("AppLifecycleState.resumed",
                      (ROOT / "lib/main.dart").read_text())

    def test_both_environments_get_distinct_app_group(self):
        path = ROOT / "ios/Flutter/BuildEnvironment.xcconfig"
        original = path.read_bytes()
        try:
            for env, bundle, group in (
                ("qa", "com.onespace.onespace.qa", "group.com.onespace.onespace.qa"),
                ("production", "com.onespace.onespace", "group.com.onespace.onespace"),
            ):
                subprocess.run([sys.executable,
                                str(ROOT / "tools/ios/configure_env.py"), env],
                               capture_output=True, text=True, check=True)
                config = path.read_text()
                self.assertIn("ONESPACE_IOS_BUNDLE_ID = " + bundle, config)
                self.assertIn("ONESPACE_SHARE_GROUP = " + group, config)
        finally:
            path.write_bytes(original)

    def test_ipa_must_contain_matching_share_extension(self):
        info = {"CFBundleIdentifier": "com.onespace.onespace",
                "OneSpaceEnvironment": "production",
                "CFBundleDisplayName": "OneSpace",
                "OneSpaceShareGroup": "group.com.onespace.onespace",
                "CFBundleURLTypes": [{"CFBundleURLSchemes": ["onespace"]}]}
        firebase = {"BUNDLE_ID": "com.onespace.onespace"}
        ext = {"CFBundleIdentifier": "com.onespace.onespace.ShareExtension",
               "OneSpaceShareGroup": "group.com.onespace.onespace.qa"}
        with tempfile.TemporaryDirectory() as temp:
            ipa = Path(temp) / "fixture.ipa"
            def write_ipa():
                with zipfile.ZipFile(ipa, "w") as z:
                    z.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(info))
                    z.writestr("Payload/Runner.app/GoogleService-Info.plist",
                               plistlib.dumps(firebase))
                    z.writestr("Payload/Runner.app/PlugIns/OneSpaceShare.appex/Info.plist",
                               plistlib.dumps(ext))
            cmd = [sys.executable, str(ROOT / "tools/ios/verify_bundle.py"),
                   "--ipa", str(ipa), "--environment", "production",
                   "--require-firebase"]
            write_ipa()
            rejected = subprocess.run(cmd, capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("wrong App Group", rejected.stderr + rejected.stdout)
            ext["OneSpaceShareGroup"] = "group.com.onespace.onespace"
            write_ipa()
            accepted = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(accepted.returncode, 0,
                             accepted.stderr + accepted.stdout)


if __name__ == "__main__":
    unittest.main()
