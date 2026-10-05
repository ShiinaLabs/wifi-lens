import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]


class CommitAuthorizationPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        cls.collaboration = (
            ROOT / ".agents/references/collaboration-rules.md"
        ).read_text(encoding="utf-8")
        cls.skill = (
            ROOT / ".agents/skills/protect-knowledge-boundary/SKILL.md"
        ).read_text(encoding="utf-8")

    def test_commit_requires_explicit_user_instruction(self):
        self.assertIn("Never commit without explicit user instruction", self.agents)
        self.assertIn("Unless the user explicitly says \"commit\"", self.collaboration)

    def test_push_requires_explicit_user_instruction(self):
        self.assertIn("Never push unless asked", self.agents)
        self.assertIn("Unless the user explicitly says \"push\"", self.collaboration)

    def test_authorized_commit_needs_no_extra_consent_question(self):
        self.assertIn(
            "Do not require a separate check-consent question before an authorized commit.",
            self.collaboration,
        )

    def test_boundary_check_is_manual_and_not_build_or_test_based(self):
        self.assertIn("Knowledge-boundary audit is opt-in", self.collaboration)
        self.assertIn("Review every changed file", self.skill)
        self.assertIn("target membership", self.skill)
        self.assertIn("manual boundary `PASS`", self.skill)

    def test_skill_is_explicitly_opt_in(self):
        self.assertIn("OPT-IN ONLY", self.skill)
        self.assertIn("do not run it automatically", self.skill)


if __name__ == "__main__":
    unittest.main()
