import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class ReplayTests(unittest.TestCase):
    def test_commands(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record = root / "record.json"
            output = root / "report.txt"
            for warning in (False, True):
                record.write_text(json.dumps({
                    "inventory": ["/boot/EFI/Linux/linux.efi"],
                    "menu": ["/boot/EFI/Linux/linux.efi"],
                    "managed_comment_misplaced": warning,
                }))
                for arguments in (("reconstruct", "--workspace", str(root)),
                                  ("report", "--output", str(output))):
                    result = subprocess.run([
                        sys.executable, str(Path(__file__).with_name("replay.py")),
                        arguments[0], str(record), *arguments[1:]
                    ], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(output.read_text(), "/boot/EFI/Linux/linux.efi\n")


if __name__ == "__main__":
    unittest.main()
