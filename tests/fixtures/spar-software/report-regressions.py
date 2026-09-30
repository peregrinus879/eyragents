class ReportTests(unittest.TestCase):
    def test_failed_scan_preserves_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record = root / "record.json"
            scanner = root / "reader.py"
            output = root / "report.txt"
            record.write_text(json.dumps({"inventory": [], "menu": ["/boot/image.efi"]}))
            for status in (0, 1, 2, 7):
                for content in ("/boot/image.efi", ""):
                    output.write_text("preserve\n")
                    scanner.write_text(f"print({content!r}) if {bool(content)!r} else None\n"
                                       f"raise SystemExit({status})\n")
                    result = subprocess.run([
                        sys.executable, str(Path(__file__).with_name("replay.py")),
                        "report", str(record), "--output", str(output),
                        "--scanner", str(scanner)
                    ], capture_output=True, text=True)
                    self.assertEqual(result.returncode, int(status > 1))
                    self.assertEqual(output.read_text(),
                                     "preserve\n" if status > 1 else content + "\n")

    def test_reconstruction_validation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            alias = root / "alias"
            alias.symlink_to(root, target_is_directory=True)
            record = root / "record.json"
            record.write_text(json.dumps({"inventory": ["/boot/image.efi"],
                                          "menu": ["/boot/image.efi"]}))

            def invoke():
                return subprocess.run([
                    sys.executable, str(Path(__file__).with_name("replay.py")),
                    "reconstruct", str(record), "--workspace", str(alias)
                ], capture_output=True, text=True).returncode

            self.assertEqual(invoke(), 0)
            for menu in (["/boot/missing.efi", "/boot/../../sentinel"],
                         ["/boot/../../sentinel", "/boot/missing.efi"]):
                record.write_text(json.dumps({"inventory": [], "menu": menu}))
                self.assertEqual(invoke(), 2)
