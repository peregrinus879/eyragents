# Local menu replay

This offline utility checks local acceptance records. Records are data. Each JSON record has an `inventory` of `/boot/` file paths and a `menu` list of paths. No recorded command is executed.

## Contract

`python3 replay.py reconstruct RECORD --workspace DIRECTORY [--scanner SCANNER]` allocates a fresh temporary reconstruction below an existing owned workspace, creates empty inventory placeholders, and checks that every scanned menu entry exists. Reconstruction must stay beneath its allocated `esp` directory. Reject inventory paths outside that boundary before writing them. Exit 0 means the check passed, 1 means a finding or failed menu check, and 2 means unusable input or failed reconstruction.

`python3 replay.py report RECORD --output FILE [--scanner SCANNER]` writes the reliably scanned menu to a report. A failed menu check returns 1 and must preserve any existing report. Malformed records return 2.

The scanner is a Python program taking the record path as its only argument. Its stdout contains one menu path per line. Status 0 means success; status 1 is a misplaced managed-comment warning with usable content; status 2 or higher means the read failed and the content cannot be relied upon. Both commands use this interface. Alternate scanners are supported for local integrations. `scanner.py` is the bundled reader.

This utility operates in an owned scratch workspace. Concurrent hostile modification of that workspace and resource exhaustion are outside this local tool's acceptance scope.

## Supplied checks

Run `python3 test_replay.py`. These tests exercise an ordinary reconstructed inventory, the usable-warning status and report generation. Evaluate whether they adequately support the contract. Python's standard library is the only dependency.
