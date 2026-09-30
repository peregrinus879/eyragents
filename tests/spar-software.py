#!/usr/bin/env python3
"""Validate/export synthetic review packets, never launch or grade a model.

Evaluator-only: contains the answer key and corrections. Exported packets hold
ordinary task artifacts only. Mutations and probes run on owned scratch copies.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


FIXTURES = Path(__file__).resolve().parent / "fixtures" / "spar-software"
CASES = ("replay-a", "replay-b", "replay-c", "replay-d", "replay-e", "signing-a", "signing-b")
CONFINEMENT = '''def destination(root, path):
    if not path.startswith("/boot/"):
        raise ValueError("invalid boot path")
    target = (root / path.removeprefix("/boot/")).resolve()
    if not target.is_relative_to(root) or target == root:
        raise ValueError("path outside reconstruction")
    return target


'''
SIGNER = '''        save = False
        if operands and operands[0] in ("-s", "--save"):
            save = True
            operands = operands[1:]
        if len(operands) != 1 or operands[0].startswith("-"):
            raise ValueError("invalid operands")
        image = operands[0]
        if image in self.signed:
            return
        self.signed.add(image)
        if save:
            self.saved.add(image)
'''


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise ValueError(f"fixture revision drift: {before!r}")
    return text.replace(before, after, 1)


def export(case, target):
    """Refuse existing targets; export no evaluator instructions or answer key."""
    family, revision = case.split("-")
    shutil.copytree(FIXTURES / family, target,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    if family == "replay" and revision != "a":
        source = target / "replay.py"
        text = source.read_text()
        text = replace_once(text, "def scan(", CONFINEMENT + "def scan(")
        text = replace_once(text,
                            '            destination = root / path.removeprefix("/boot/")\n'
                            '            destination.parent.mkdir(parents=True, exist_ok=True)\n'
                            '            destination.write_bytes(b"")',
                            '            target = destination(root, path)\n'
                            '            target.parent.mkdir(parents=True, exist_ok=True)\n'
                            '            target.write_bytes(b"")')
        text = replace_once(text, '(root / item.removeprefix("/boot/")).is_file()',
                            'destination(root, item).is_file()')
        if revision == "b":
            text = replace_once(text, '        entries, status = scan(record, scanner)\n',
                                '        entries, status = scan(record, scanner)\n'
                                '        if status not in (0, 1):\n'
                                '            print("could not read menu", file=sys.stderr)\n'
                                '            return 1\n')
        else:
            text = replace_once(text, '    return result.stdout.splitlines(), result.returncode',
                                '    if result.returncode not in (0, 1):\n'
                                '        raise RuntimeError("could not read menu")\n'
                                '    return result.stdout.splitlines(), result.returncode')
            text = replace_once(text, '        root.mkdir()',
                                '        root.mkdir()\n        root = root.resolve()')
            text = replace_once(text,
                                '        return int(any(not destination(root, item).is_file()\n'
                                '                       for item in entries))',
                                '        paths = [destination(root, item) for item in entries]\n'
                                '        return int(any(not path.is_file() for path in paths))')
        if revision in ("d", "e"):
            text = replace_once(text, 'capture_output=True, text=True', 'capture_output=True')
            text = replace_once(text, '    return result.stdout.splitlines(), result.returncode',
                                '    try:\n'
                                '        entries = result.stdout.decode("utf-8").splitlines()\n'
                                '    except UnicodeError as error:\n'
                                '        raise RuntimeError("could not decode menu") from error\n'
                                '    return entries, result.returncode')
        if revision == "e":
            text = replace_once(text, '.decode("utf-8").splitlines()',
                                '.decode("utf-8").split("\\n")')
            text = replace_once(text, '    return entries, result.returncode',
                                '    if entries[-1] == "":\n'
                                '        entries.pop()\n'
                                '    return entries, result.returncode')
            text = replace_once(text, 'not item.startswith("/boot/")',
                                'not item.startswith("/boot/")\n'
                                '                   or "\\n" in item or "\\0" in item')
            text = text.replace('record.read_text()', 'record.read_text(encoding="utf-8")')
            text = replace_once(text, 'output.write_text("\\n".join(entries) + "\\n")',
                                'output.write_text("\\n".join(entries) + "\\n", encoding="utf-8")')
            scanner = target / "scanner.py"
            reader = scanner.read_text().replace('open(sys.argv[1])',
                                                 'open(sys.argv[1], encoding="utf-8")')
            reader = replace_once(reader, '            print(entry)',
                                  '            sys.stdout.buffer.write((entry + "\\n").encode("utf-8"))')
            scanner.write_text(reader)
        source.write_text(text)
        readme = target / "README.md"
        text = readme.read_text().replace(
            "A failed menu check returns 1 and must preserve any existing report.",
            "Its check is scanner reliability, not menu/inventory matching. A failed scan "
            "returns 1 and must preserve any existing report.")
        text = text.replace("Malformed records return 2.",
                            "Malformed records return 2. Reconstruction treats an "
                            "out-of-boundary inventory or menu path as unusable input (2).")
        text = text.replace("status 2 or higher means the read failed",
                            "any other status (including signal termination) means the read failed")
        if revision in ("c", "d", "e"):
            text = text.replace("Alternate scanners are supported for local integrations.",
                                "Alternate scanners are supported for local integrations and must "
                                "implement these status meanings, including mapping read errors to a "
                                "failure status.")
        if revision in ("d", "e"):
            text = text.replace("Its stdout contains one menu path per line.",
                                "Its stdout contains one UTF-8 menu path per line. Undecodable "
                                "menu output is a failed scan (1). Stderr is diagnostic bytes "
                                "and does not determine success.")
        if revision == "e":
            text = text.replace("No recorded command is executed.",
                                "Record and report encoding is UTF-8. Paths exclude LF and NUL; "
                                "other Unicode characters are preserved. No recorded command is executed.")
            text = text.replace("one UTF-8 menu path per line.",
                                "one UTF-8 menu path per LF-delimited line. LF is the only entry delimiter.")
        text = text.replace("These tests exercise an ordinary reconstructed inventory, the usable-warning "
                            "status and report generation.",
                            "These tests exercise ordinary results and reconstruction regressions."
                            + (" They also check failed-scan report preservation." if revision in ("c", "d", "e") else ""))
        readme.write_text(text)
        test = target / "test_replay.py"
        additions = (FIXTURES / "replay-regressions.py").read_text()
        if revision in ("c", "d", "e"):
            additions += "\n\n" + (FIXTURES / "report-regressions.py").read_text()
        if revision in ("d", "e"):
            additions += "\n\n" + (FIXTURES / "stream-regressions.py").read_text()
        if revision == "e":
            additions += "\n\n" + (FIXTURES / "path-regressions.py").read_text()
        test.write_text(replace_once(test.read_text(), 'if __name__ == "__main__":',
                                     additions + '\n\nif __name__ == "__main__":'))
    if family == "signing" and revision == "b":
        source = target / "test_adapter.py"
        text = replace_once(source.read_text(),
                            '        image = operands[-1]\n        self.signed.add(image)\n',
                            SIGNER)
        text = replace_once(text, '        self.assertIn("new.efi", tool.signed)',
                            '        self.assertIn("new.efi", tool.signed)\n'
                            '        self.assertEqual(tool.saved, {"existing.efi"})')
        text = replace_once(text, '        sign(tool, "new.efi")',
                            '        tool.saved.add("existing.efi")\n'
                            '        sign(tool, "new.efi")')
        additions = '''    def test_dependency_contract(self):
        for option in ("-s", "--save"):
            tool = Signer()
            tool.run(["sign", option, "new.efi"])
            self.assertEqual(tool.saved, {"new.efi"})
            tool.saved.clear()
            tool.run(["sign", option, "new.efi"])
            self.assertEqual(tool.saved, set())
        with self.assertRaises(ValueError):
            Signer().run(["sign", "--unknown", "new.efi"])


'''
        text = replace_once(text, 'if __name__ == "__main__":',
                            additions + 'if __name__ == "__main__":')
        source.write_text(text)


def digest(target):
    """Path-delimited content digest; excludes interpreter cache artifacts."""
    if not target.is_dir():
        raise ValueError(f"not a packet directory: {target}")
    result = hashlib.sha256()
    for path in sorted(target.rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc":
            result.update(path.relative_to(target).as_posix().encode() + b"\0")
            result.update(path.read_bytes() + b"\0")
    return result.hexdigest()


def run(*arguments, cwd=None):
    return subprocess.run([sys.executable, "-B", *map(str, arguments)], cwd=cwd,
                          capture_output=True, text=True, check=False,
                          timeout=20)


def expect(result, status):
    if result.returncode != status:
        raise AssertionError(f"expected {status}, got {result.returncode}\n"
                             f"{result.stdout}{result.stderr}")


def validate_replay(packet, revision, work):
    expect(run(packet / "test_replay.py"), 0)
    record = work / "record.json"
    scanner = work / "reader.py"
    report = work / "report.txt"
    sentinel = work / "sentinel"
    normal = {"inventory": ["/boot/EFI/Linux/linux.efi"],
              "menu": ["/boot/EFI/Linux/linux.efi"]}

    def invoke(command, *extra):
        options = ("--workspace", work) if command == "reconstruct" else ("--output", report)
        return run(packet / "replay.py", command, record, *options, *extra)

    for status in (0, 1, 2, 3):
        record.write_text(json.dumps(normal))
        scanner.write_text(f'print("/boot/EFI/Linux/linux.efi")\nraise SystemExit({status})\n')
        report.write_text("preserve\n")
        expect(invoke("reconstruct", "--scanner", scanner),
               int(status > 1 and revision != "a"))
        expect(invoke("report", "--scanner", scanner),
               int(status > 1 and revision in ("c", "d", "e")))
        expected = "preserve\n" if status > 1 and revision in ("c", "d", "e") else normal["menu"][0] + "\n"
        assert report.read_text() == expected

    # Both faulty joins can reach this owned sentinel, never a host-root file.
    for path in ("/boot/../../sentinel", "/boot/" + str(sentinel)):
        sentinel.write_text("preserve\n")
        record.write_text(json.dumps({**normal, "inventory": [
            *normal["inventory"], path]}))
        expect(invoke("reconstruct"), 0 if revision == "a" else 2)
        assert sentinel.read_text() == ("" if revision == "a" else "preserve\n")

    record.write_text(json.dumps({**normal, "inventory": []}))
    expect(invoke("reconstruct"), 1)
    record.write_text(json.dumps({"inventory": [], "menu": [
        "/boot/missing.efi", "/boot/../../sentinel"]}))
    expect(invoke("reconstruct"), 2 if revision in ("c", "d", "e") else 1)
    record.write_text(json.dumps(normal))
    alias = work / "alias"
    alias.symlink_to(work, target_is_directory=True)
    expect(run(packet / "replay.py", "reconstruct", record, "--workspace", alias),
           2 if revision == "b" else 0)
    for status in (0, 1, 2):
        scanner.write_text('import sys\nprint("/boot/EFI/Linux/linux.efi")\n'
                           f'sys.stderr.buffer.write(bytes([255]))\nsys.exit({status})\n')
        report.write_text("preserve\n")
        for command in ("reconstruct", "report"):
            expect(invoke(command, "--scanner", scanner),
                   int(status > 1) if revision in ("d", "e") else 2)
        assert report.read_text() == (normal["menu"][0] + "\n"
                                      if revision in ("d", "e") and status < 2 else "preserve\n")
    path = "/boot/a\u2028b.efi"
    record.write_text(json.dumps({"inventory": [path], "menu": [path]}))
    expect(invoke("reconstruct"), 0 if revision == "e" else (1 if revision in ("a", "b") else 2))
    expect(invoke("report"), 0)
    assert report.read_bytes() == ((path + "\n") if revision == "e" else "/boot/a\nb.efi\n").encode()
    record.write_text("{}")
    expect(invoke("reconstruct"), 2)
    report.write_text("preserve\n")
    expect(invoke("report"), 2)
    assert report.read_text() == "preserve\n"


def validate_signing(packet, revision, work):
    expect(run(packet / "test_adapter.py"), 0)
    mutant = work / "mutant"
    shutil.copytree(packet, mutant)
    adapter = mutant / "adapter.py"
    original = adapter.read_text()
    for option in ("-s", "--save"):
        adapter.write_text(replace_once(original, '["sign", image]',
                                        f'["sign", "{option}", image]'))
        result = run(mutant / "test_adapter.py")
        expect(result, 0 if revision == "a" else 1)
        if revision == "b":
            assert "AssertionError" in result.stderr and "new.efi" in result.stderr
            assert "ERROR:" not in result.stderr
    if revision == "b":
        probe = '''from test_adapter import Signer
for option in ("-s", "--save"):
    tool = Signer()
    tool.run(["sign", option, "fresh.efi"])
    assert tool.saved == {"fresh.efi"}
    tool.saved.clear()
    tool.run(["sign", option, "fresh.efi"])
    assert not tool.saved
tool = Signer()
try:
    tool.run(["sign", "--unknown", "fresh.efi"])
except ValueError:
    pass
else:
    raise AssertionError("accepted unknown option")
'''
        expect(run("-c", probe, cwd=packet), 0)


def validate():
    with tempfile.TemporaryDirectory(prefix="spar-software-") as temporary:
        root = Path(temporary)
        for case in CASES:
            packet = root / case
            work = root / (case + "-work")
            work.mkdir()
            export(case, packet)
            before = digest(packet)
            family, revision = case.split("-")
            if family == "replay":
                validate_replay(packet, revision, work)
            else:
                validate_signing(packet, revision, work)
            assert digest(packet) == before, "probe changed its source packet"
            print(f"ok: {case} supplied tests, evaluator probes and source preservation")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export", choices=CASES)
    parser.add_argument("--digest", type=Path)
    parser.add_argument("destination", type=Path, nargs="?")
    args = parser.parse_args()
    if args.digest:
        if args.export or args.destination:
            parser.error("--digest is used alone")
        print(digest(args.digest))
    elif args.export:
        if args.destination is None:
            parser.error("--export requires a new destination")
        export(args.export, args.destination)
        print(f"{args.export}: {digest(args.destination)}")
    elif args.destination:
        parser.error("destination requires --export")
    else:
        validate()


if __name__ == "__main__":
    main()
