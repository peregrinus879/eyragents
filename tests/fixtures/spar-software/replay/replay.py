import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def scan(record, scanner):
    result = subprocess.run(
        [sys.executable, str(scanner), str(record)], capture_output=True, text=True
    )
    return result.stdout.splitlines(), result.returncode


def reconstruct(record, scanner, workspace):
    inventory = json.loads(record.read_text())["inventory"]
    with tempfile.TemporaryDirectory(dir=workspace) as temporary:
        root = Path(temporary) / "esp"
        root.mkdir()
        for path in inventory:
            destination = root / path.removeprefix("/boot/")
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(b"")
        entries, status = scan(record, scanner)
        return int(any(not (root / item.removeprefix("/boot/")).is_file()
                       for item in entries))


def report(record, scanner, output):
    entries, status = scan(record, scanner)
    output.write_text("\n".join(entries) + "\n")
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("reconstruct", "report"))
    parser.add_argument("record", type=Path)
    parser.add_argument("--scanner", type=Path, default=Path(__file__).with_name("scanner.py"))
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.command == "reconstruct" and args.workspace is None:
        parser.error("reconstruct requires --workspace")
    if args.command == "report" and args.output is None:
        parser.error("report requires --output")
    try:
        data = json.loads(args.record.read_text())
        if not isinstance(data, dict) or any(
            not isinstance(data.get(key), list)
            or any(not isinstance(item, str) or not item.startswith("/boot/")
                   for item in data[key])
            for key in ("inventory", "menu")
        ) or not isinstance(data.get("managed_comment_misplaced", False), bool):
            raise ValueError("invalid record")
        if args.command == "reconstruct":
            return reconstruct(args.record, args.scanner, args.workspace)
        return report(args.record, args.scanner, args.output)
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
