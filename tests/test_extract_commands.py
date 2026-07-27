import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import extract_commands  # noqa: E402


SAMPLE_SOURCE = """
cmd.add({"hello", "hi"}, {"hello <name>", "Say hello"}, function(name)
end)

cmd.addPatched({"oldhello"}, {"oldhello", "Legacy hello"}, function()
end)
"""


class ExtractCommandsTests(unittest.TestCase):
	def test_build_result_extracts_normal_and_patched_commands(self):
		result = extract_commands.build_result(SAMPLE_SOURCE)

		self.assertEqual(result["commands"][0]["name"], "hello")
		self.assertEqual(result["commands"][0]["aliases"], ["hello", "hi"])
		self.assertEqual(result["commands"][0]["args"], "<name>")
		self.assertEqual(result["patched_commands"][0]["name"], "oldhello")

	def test_duplicate_canonical_name_is_an_error(self):
		result = extract_commands.build_result(
			"""
			cmd.add({"same", "one"}, {"same", "First"}, function() end)
			cmd.add({"same", "two"}, {"same", "Second"}, function() end)
			"""
		)

		errors, warnings = extract_commands.validation_messages(result)

		self.assertTrue(any("duplicate canonical command name 'same'" in item for item in errors))
		self.assertTrue(any("duplicate command alias 'same'" in item for item in warnings))

	def test_alias_collision_warns_unless_strict(self):
		result = extract_commands.build_result(
			"""
			cmd.add({"first", "shared"}, {"first", "First"}, function() end)
			cmd.add({"second", "shared"}, {"second", "Second"}, function() end)
			"""
		)

		errors, warnings = extract_commands.validation_messages(result)
		strict_errors, strict_warnings = extract_commands.validation_messages(
			result, strict_aliases=True
		)

		self.assertEqual(errors, [])
		self.assertTrue(any("duplicate command alias 'shared'" in item for item in warnings))
		self.assertTrue(any("duplicate command alias 'shared'" in item for item in strict_errors))
		self.assertEqual(strict_warnings, [])

	def test_check_mode_detects_fresh_and_stale_output(self):
		with tempfile.TemporaryDirectory() as directory:
			root = Path(directory)
			source = root / "Source.lua"
			output = root / "commands.json"
			source.write_text(SAMPLE_SOURCE, encoding="utf-8")
			output.write_text(
				json.dumps(extract_commands.build_result(SAMPLE_SOURCE), indent=2),
				encoding="utf-8",
			)

			with mock.patch.object(
				sys,
				"argv",
				[
					"extract_commands.py",
					"--source",
					str(source),
					"--output",
					str(output),
					"--check",
				],
			), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(
				io.StringIO()
			):
				self.assertEqual(extract_commands.main(), 0)

			output.write_text('{"commands": [], "patched_commands": []}', encoding="utf-8")
			stderr = io.StringIO()
			with mock.patch.object(
				sys,
				"argv",
				[
					"extract_commands.py",
					"--source",
					str(source),
					"--output",
					str(output),
					"--check",
				],
			), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
				self.assertEqual(extract_commands.main(), 1)

			self.assertIn("is stale", stderr.getvalue())


if __name__ == "__main__":
	unittest.main()
