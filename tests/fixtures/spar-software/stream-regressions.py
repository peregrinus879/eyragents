class ScannerStreamTests(unittest.TestCase):
    def test_status_precedes_decoding(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record = root / "record.json"
            scanner = root / "reader.py"
            output = root / "report.txt"
            record.write_text(json.dumps({"inventory": ["/boot/image.efi"],
                                          "menu": ["/boot/image.efi"]}))
            readers = []
            for status in (0, 1, 2):
                readers.append((f'import sys\nprint("/boot/image.efi")\n'
                                f'sys.stderr.buffer.write(bytes([255]))\nsys.exit({status})\n',
                                int(status > 1)))
            for status in (0, 1, 2):
                readers.append((f'import sys\nsys.stdout.buffer.write(bytes([255]))\n'
                                f'sys.exit({status})\n', 1))
            readers.append(('import os, signal\n'
                            'os.kill(os.getpid(), signal.SIGTERM)\n', 1))
            for source, expected in readers:
                scanner.write_text(source)
                for command, options in (("reconstruct", ("--workspace", root)),
                                         ("report", ("--output", output))):
                    output.write_text("preserve\n")
                    result = subprocess.run([
                        sys.executable, str(Path(__file__).with_name("replay.py")),
                        command, str(record), *map(str, options), "--scanner", str(scanner)
                    ], capture_output=True)
                    self.assertEqual(result.returncode, expected, result.stderr)
                    if command == "report":
                        self.assertEqual(output.read_text(),
                                         "preserve\n" if expected else "/boot/image.efi\n")

    def test_malformed_record_preserves_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record = root / "record.json"
            output = root / "report.txt"
            for data in ({"inventory": "x", "menu": []},
                         {"inventory": [], "menu": [], "managed_comment_misplaced": 1}):
                record.write_text(json.dumps(data))
                for command, options in (("reconstruct", ("--workspace", root)),
                                         ("report", ("--output", output))):
                    output.write_text("preserve\n")
                    result = subprocess.run([
                        sys.executable, str(Path(__file__).with_name("replay.py")),
                        command, str(record), *map(str, options)
                    ], capture_output=True)
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertEqual(output.read_text(), "preserve\n")
