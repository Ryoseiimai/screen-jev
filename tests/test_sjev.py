#!/usr/bin/env python3
"""sjev の単体テスト(標準ライブラリunittestのみ)。"""
import importlib.util
import json
import os
import sys
import tempfile
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN_PATH = os.path.join(ROOT, "bin", "sjev")

spec = importlib.util.spec_from_loader("sjev_mod", loader=None, origin=BIN_PATH)
sjev = importlib.util.module_from_spec(spec)
sjev.__dict__["__file__"] = BIN_PATH
with open(BIN_PATH, encoding="utf-8") as f:
    src = f.read()
exec(compile(src, BIN_PATH, "exec"), sjev.__dict__)  # noqa: S102


class TestMask(unittest.TestCase):
    def test_email_masked(self):
        self.assertIn("[伏せ字]", sjev.mask_sensitive("連絡先: taro@example.com です"))
        self.assertNotIn("taro@example.com", sjev.mask_sensitive("taro@example.com"))

    def test_api_token_masked(self):
        text = "key=sk-abcdefghij1234567890"
        self.assertNotIn("sk-abcdefghij1234567890", sjev.mask_sensitive(text))

    def test_github_token_masked(self):
        text = "ghp_ABCDEFGHIJ1234567890abcd"
        self.assertNotIn(text, sjev.mask_sensitive(text))

    def test_card_number_masked(self):
        text = "4111 1111 1111 1111"
        self.assertNotIn("4111 1111 1111 1111", sjev.mask_sensitive(text))

    def test_anthropic_token_masked(self):
        text = "key=sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890"
        self.assertNotIn("sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890", sjev.mask_sensitive(text))

    def test_google_token_masked(self):
        text = "AIzaSyDaGmWKa4JsXZ-HjGw7ISLn_3namBGewQe"
        self.assertNotIn(text, sjev.mask_sensitive(text))

    def test_jwt_masked(self):
        text = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        self.assertNotIn(text, sjev.mask_sensitive(text))

    def test_github_pat_masked(self):
        text = "github_pat_11ABCDEFG0123456789abcdefghijklmnopqrstuvwxyz"
        self.assertNotIn(text, sjev.mask_sensitive(text))

    def test_stripe_key_masked(self):
        text = "sk_live_51ABCDEFGHIJKLMNOPQRSTUVWX"
        self.assertNotIn(text, sjev.mask_sensitive(text))

    def test_phone_number_masked(self):
        text = "電話番号: 090-3433-5181 です"
        self.assertNotIn("090-3433-5181", sjev.mask_sensitive(text))

    def test_labeled_password_masked(self):
        text = "password: hunter2fun!"
        self.assertNotIn("hunter2fun!", sjev.mask_sensitive(text))

    def test_normal_text_untouched(self):
        text = "こんにちは、今日は良い天気です"
        self.assertEqual(text, sjev.mask_sensitive(text))


class TestJevOptIn(unittest.TestCase):
    def test_default_config_jev_off(self):
        self.assertFalse(sjev.DEFAULT_CONFIG.get("jev"))

    def test_call_jev_returns_none_when_disabled(self):
        self.assertIsNone(sjev.call_jev("app=X title=Y\nsome text", {"jev": False}))

    def test_call_jev_returns_none_without_key_even_if_enabled(self):
        orig = sjev.API_KEY_PATH
        sjev.API_KEY_PATH = "/nonexistent/path/for/test"
        try:
            self.assertIsNone(sjev.call_jev("app=X title=Y\nsome text", {"jev": True}))
        finally:
            sjev.API_KEY_PATH = orig


class TestExclude(unittest.TestCase):
    def setUp(self):
        self.cfg = sjev.DEFAULT_CONFIG

    def test_excluded_app(self):
        self.assertTrue(sjev.is_excluded("1Password 8", "some title", self.cfg))

    def test_excluded_title_word(self):
        self.assertTrue(sjev.is_excluded("Chrome", "パスワードを入力してください", self.cfg))

    def test_not_excluded(self):
        self.assertFalse(sjev.is_excluded("Visual Studio Code", "main.py", self.cfg))


class TestDuration(unittest.TestCase):
    def test_minutes(self):
        self.assertEqual(sjev.parse_duration("30m"), 1800)

    def test_hours(self):
        self.assertEqual(sjev.parse_duration("1h"), 3600)

    def test_seconds(self):
        self.assertEqual(sjev.parse_duration("90s"), 90)

    def test_invalid(self):
        with self.assertRaises(ValueError):
            sjev.parse_duration("abc")


class TestTimelinePrune(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.orig_data_dir = sjev.DATA_DIR
        self.orig_timeline = sjev.TIMELINE_PATH
        sjev.DATA_DIR = self.tmpdir
        sjev.TIMELINE_PATH = os.path.join(self.tmpdir, "timeline.jsonl")

    def tearDown(self):
        sjev.DATA_DIR = self.orig_data_dir
        sjev.TIMELINE_PATH = self.orig_timeline

    def test_prune_removes_old_entries(self):
        now = time.time()
        old = now - sjev.RETENTION_SECONDS - 3600
        sjev.append_timeline({"ts": old, "app": "Old", "kind": "front", "text": "old"})
        sjev.append_timeline({"ts": now, "app": "New", "kind": "front", "text": "new"})
        sjev.prune_timeline()
        entries = sjev.read_timeline()
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["app"], "New")


class TestHookOutput(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.orig_data_dir = sjev.DATA_DIR
        self.orig_timeline = sjev.TIMELINE_PATH
        sjev.DATA_DIR = self.tmpdir
        sjev.TIMELINE_PATH = os.path.join(self.tmpdir, "timeline.jsonl")
        now = time.time()
        sjev.append_timeline({
            "ts": now - 30, "app": "Google Chrome", "bundle": "com.google.Chrome",
            "title": "調べ物", "kind": "front", "text": "テスト用の画面内容です",
        })

    def tearDown(self):
        sjev.DATA_DIR = self.orig_data_dir
        sjev.TIMELINE_PATH = self.orig_timeline

    def test_build_context_within_limit(self):
        ctx = sjev.build_context()
        self.assertLessEqual(len(ctx), sjev.HOOK_MAX_CHARS)
        self.assertIn("[画面Jev]", ctx)
        self.assertIn("テスト用の画面内容です", ctx)

    def test_unattended_detection(self):
        os.environ["CLAUDE_CODE_ENTRYPOINT"] = "cli"
        self.assertFalse(sjev.is_unattended())
        os.environ["CLAUDE_CODE_ENTRYPOINT"] = "sdk-cli"
        self.assertTrue(sjev.is_unattended())
        os.environ.pop("CLAUDE_CODE_ENTRYPOINT", None)
        self.assertTrue(sjev.is_unattended())


if __name__ == "__main__":
    unittest.main()
