class ReconstructionTests(unittest.TestCase):
    def test_boundaries_and_results(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            record = root / "record.json"
            scanner = root / "reader.py"
            sentinel = root / "sentinel"
            normal = {"inventory": ["/boot/image.efi"], "menu": ["/boot/image.efi"]}

            def invoke(*extra):
                return subprocess.run([
                    sys.executable, str(Path(__file__).with_name("replay.py")),
                    "reconstruct", str(record), "--workspace", str(root), *map(str, extra)
                ], capture_output=True, text=True).returncode

            for path in ("/boot/../../sentinel", "/boot/" + str(sentinel)):
                for field in ("inventory", "menu"):
                    sentinel.write_text("preserve\n")
                    record.write_text(json.dumps({**normal, field: [path]}))
                    self.assertEqual(invoke(), 2)
                    self.assertEqual(sentinel.read_text(), "preserve\n")
            record.write_text(json.dumps({**normal, "inventory": []}))
            self.assertEqual(invoke(), 1)
            record.write_text("{}")
            self.assertEqual(invoke(), 2)
            record.write_text(json.dumps(normal))
            for status in (0, 1, 2, 7):
                for output in ("/boot/image.efi", ""):
                    scanner.write_text(f"print({output!r}) if {bool(output)!r} else None\n"
                                       f"raise SystemExit({status})\n")
                    self.assertEqual(invoke("--scanner", scanner), int(status > 1))
            self.assertEqual(invoke("--scanner", root / "absent.py"), 1)
