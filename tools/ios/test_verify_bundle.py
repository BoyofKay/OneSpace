"""Pure-Python checks for iOS QA/production bundle isolation."""
import unittest
from verify_bundle import verify

def bundle(environment, identifier, scheme, display):
    return {
        "OneSpaceEnvironment": environment,
        "CFBundleIdentifier": identifier,
        "OneSpaceShareGroup": "group." + identifier,
        "CFBundleDisplayName": display,
        "CFBundleURLTypes": [{"CFBundleURLSchemes": [scheme]}],
    }

class BundleVerificationTests(unittest.TestCase):
    def test_qa_passes(self):
        verify(bundle("qa", "com.onespace.onespace.qa", "onespace-preview", "OneSpace QA"), "qa")
    def test_production_passes(self):
        verify(bundle("production", "com.onespace.onespace", "onespace", "OneSpace"), "production")
    def test_qa_cannot_use_production_bundle(self):
        with self.assertRaises(SystemExit):
            verify(bundle("qa", "com.onespace.onespace", "onespace-preview", "OneSpace QA"), "qa")
    def test_prod_rejects_qa_callback(self):
        with self.assertRaises(SystemExit):
            verify(bundle("production", "com.onespace.onespace", "onespace-preview", "OneSpace"), "production")
    def test_prod_rejects_qa_environment(self):
        with self.assertRaises(SystemExit):
            verify(bundle("qa", "com.onespace.onespace", "onespace", "OneSpace"), "production")

if __name__ == "__main__":
    unittest.main()
