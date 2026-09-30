class PathFramingTests(unittest.TestCase):
    def test_path_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record = root / "record.json"
            output = root / "report.txt"
            for path in ("/boot/é.efi", "/boot/a\u0085b.efi", "/boot/a\u2028b.efi",
                         "/boot/a\rb.efi", "/boot/a\nb.efi", "/boot/a\0b.efi"):
                record.write_text(json.dumps({"inventory": [path], "menu": [path]}),
                                  encoding="utf-8")
                expected = 2 if "\n" in path or "\0" in path else 0
                for command, options in (("reconstruct", ("--workspace", root)),
                                         ("report", ("--output", output))):
                    output.write_bytes(b"preserve\n")
                    result = subprocess.run([
                        sys.executable, str(Path(__file__).with_name("replay.py")),
                        command, str(record), *map(str, options)
                    ], capture_output=True)
                    self.assertEqual(result.returncode, expected, result.stderr)
                    if command == "report":
                        self.assertEqual(output.read_bytes(), b"preserve\n" if expected
                                         else (path + "\n").encode("utf-8"))
