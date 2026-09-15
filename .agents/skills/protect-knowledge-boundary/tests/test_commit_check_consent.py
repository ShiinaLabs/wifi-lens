import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
QUESTION = "Run the checks relevant to this commit before committing?"


class CommitCheckConsentPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        cls.collaboration = (
            ROOT / ".agents/references/collaboration-rules.md"
        ).read_text(encoding="utf-8")

    def test_agents_requires_the_consent_question_before_every_commit(self):
        self.assertIn(QUESTION, self.agents)
        self.assertIn("before every commit", self.agents.lower())

    def test_collaboration_rules_define_yes_behavior(self):
        self.assertIn(QUESTION, self.collaboration)
        self.assertIn("If the user answers yes", self.collaboration)
        self.assertIn("run fresh checks", self.collaboration)

    def test_collaboration_rules_define_no_behavior(self):
        self.assertIn("If the user answers no", self.collaboration)
        self.assertIn("skipped by user choice", self.collaboration)

    def test_collaboration_rules_define_unanswered_behavior(self):
        self.assertIn("If the user has not answered", self.collaboration)
        self.assertIn("neither run pre-commit checks nor commit", self.collaboration)

    def test_consent_applies_to_only_one_commit(self):
        self.assertIn("Consent applies to one commit request only", self.collaboration)

    def test_boundary_check_is_manual_and_not_build_or_test_based(self):
        self.assertIn("Boundary verification", self.collaboration)
        self.assertIn("manual module-by-module review", self.collaboration)
        self.assertIn("Build success", self.collaboration)
        self.assertIn("unit-test results", self.collaboration)
        self.assertIn("cannot establish a boundary", self.collaboration)
        self.assertNotIn(
            "all code changes must be verified by running `xcodebuild build` successfully",
            self.collaboration,
        )


if __name__ == "__main__":
    unittest.main()
