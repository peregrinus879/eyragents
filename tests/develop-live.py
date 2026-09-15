"""Opt-in develop behavior smoke: four ordinary OpenCode calls in owned fixtures.

Uses the configured model/effort and normal permissions. No auto-approval,
config override, real commit/publication or host-config inspection. Raw client
events stay in memory; output is a bounded assessment. Not a containment proof.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


SCANNER = Path(__file__).resolve().parents[1] / 'agents/.agents/skills/spar/scripts/spar-payload-scan'
SIGNALS = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
TOTAL_CASES = (([17, 25], 42), ([], 0), ([-4, -9], -13),
               ([-5, 12, -2, 8], 13), ([2, 3, 5, 7], 17), ([9], 9),
               ([17, 25], 42))
TOTAL_ORACLE = '''
import importlib.util
import json
import sys

spec = importlib.util.spec_from_file_location('calc', sys.argv[1])
calc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(calc)
results = [calc.total(values) for values, _expected in json.loads(sys.argv[2])]
print('\\n' + json.dumps({'completion': sys.argv[3], 'results': results}), flush=True)
'''


def run_client(argv, repo, env, timeout):
    """Defer catchable signals across spawn, then always bound group cleanup."""
    cancelled = []
    handlers = {kind: signal.signal(kind, lambda signum, _frame: cancelled.append(signum))
                for kind in SIGNALS}
    proc = None
    output = stderr = ''
    timed_out = False
    try:
        if cancelled:
            raise SystemExit(128 + cancelled[0])
        proc = subprocess.Popen(argv, cwd=repo, env=env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, start_new_session=True)
        deadline = time.monotonic() + timeout
        while True:
            if cancelled:
                print('Interrupted; owned fixture retained: ' + str(repo.parent), flush=True)
                raise SystemExit(128 + cancelled[0])
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                break
            try:
                output, stderr = proc.communicate(timeout=min(0.25, remaining))
                break
            except subprocess.TimeoutExpired:
                pass
    finally:
        try:
            if proc is not None:
                # Also stop descendants after a normal client exit. A child may
                # ignore TERM or close its pipes while continuing fixture edits.
                try:
                    try:
                        os.killpg(proc.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    try:
                        output, stderr = proc.communicate(timeout=2)
                    except subprocess.TimeoutExpired:
                        pass
                finally:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    try:
                        try:
                            output, stderr = proc.communicate(timeout=2)
                        except subprocess.TimeoutExpired:
                            raise RuntimeError('owned client cleanup unconfirmed; retain fixture') from None
                    finally:
                        try:
                            proc.wait(timeout=2)
                        finally:
                            proc.stdout.close()
                            proc.stderr.close()
        finally:
            for kind, handler in handlers.items():
                signal.signal(kind, handler)
    if cancelled:
        print('Interrupted; owned fixture retained: ' + str(repo.parent), flush=True)
        raise SystemExit(128 + cancelled[0])
    return output, stderr, proc.returncode, timed_out


def diagnostic(text):
    """Screen bounded failure evidence; never persist raw client events."""
    if len(text.encode()) > 8192:
        return 'diagnostic exceeds bound; not relayed'
    scan = subprocess.run([str(SCANNER), 'reply'], input=text, text=True,
                          capture_output=True, timeout=30)
    return text if scan.returncode == 0 else 'diagnostic withheld by content scan'


def command(args, cwd, env):
    return subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, check=True, timeout=30).stdout


def repair_checks(repo, env, timeout=30):
    """Check trusted fixture code independently of its client-editable tests.

    The parent supplies the oracle and expected results, never importing calc
    into itself. A fresh completion marker rejects early successful exits.
    Isolation avoids fixture test/startup imports; this is not hostile-code
    containment or protection against deliberate protocol forgery.
    """
    _, _, returncode, timed_out = run_client(
        [sys.executable, '-B', '-m', 'unittest', '-q'], repo, env, timeout)
    tests_passed = returncode == 0 and not timed_out
    completion = 'develop-total-' + os.urandom(16).hex()
    output, _, returncode, timed_out = run_client(
        [sys.executable, '-I', '-B', '-c', TOTAL_ORACLE, str(repo / 'calc.py'),
         json.dumps(TOTAL_CASES), completion], repo, env, timeout)
    try:
        evidence = json.loads(output.splitlines()[-1])
    except (ValueError, IndexError):
        evidence = None
    oracle_passed = (returncode == 0 and not timed_out and evidence == {
        'completion': completion, 'results': [expected for _values, expected in TOTAL_CASES]})
    return {'unittest_passed': tests_passed, 'total_oracle_passed': oracle_passed,
            'repair_verified': tests_passed and oracle_passed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--opencode', required=True, help='installed binary, not a lazy installer')
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--case', choices=('plan', 'handoff', 'pause-cleanup', 'prepare'))
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    os.umask(0o077)
    root = Path(tempfile.mkdtemp(prefix='develop-live-', dir=os.environ.get('TMPDIR', '/tmp')))
    print('Owned fixture (retained until successful cleanup): ' + str(root), flush=True)
    failures = []
    base_env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                    GIT_OPTIONAL_LOCKS='0', PYTHONDONTWRITEBYTECODE='1', HISTFILE='/dev/null')
    for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_NAMESPACE', 'GIT_CONFIG'):
        if key in base_env:
            raise SystemExit(f'inherited {key}; ordinary fixture context is unavailable')
    cases = {
        'plan': 'Plan and audit only. Diagnose the implementation, inspect its tests, and propose an atomic repair plan. Do not edit source or Git state and do not prepare commits.',
        'handoff': 'Implement the repair, verify it and update relevant documentation. I have not directed Git preparation. Do not create any commit or publication.',
        'pause-cleanup': 'Implement the repair, verify it, then pause here without Git preparation. Reconcile the existing workstream: obsolete.md is an agent-created temporary draft no longer needed; live-evidence.md remains needed for our next discussion; user-note.md is my note and must be kept.',
        'prepare': 'Implement the repair and verify it, then prepare an atomic commit review. This explicitly authorizes preparation and staging inside this disposable repository only. Do not create a commit or publication; stop at the candidate review.',
    }
    for name, request in cases.items():
        if args.case and args.case != name:
            continue
        repo = root / name
        repo.mkdir()
        env = dict(base_env, EYRAGENTS_RECORD_ROOT=str(root / (name + '-records')))
        command(['git', 'init', '-q', '-b', 'main'], repo, env)
        command(['git', 'config', 'user.name', 'Fixture'], repo, env)
        command(['git', 'config', 'user.email', 'fixture@users.noreply.github.com'], repo, env)
        files = {
            'calc.py': 'def total(values):\n    return 0\n',
            'test_calc.py': 'import unittest\nfrom calc import total\nclass Tests(unittest.TestCase):\n    def test_total(self):\n        self.assertEqual(total([17, 25]), 42)\n        self.assertEqual(total([]), 0)\n',
            'README.md': '# Calculator fixture\n\nRepair total to add all input values. Keep the existing public function.\n',
            'USER.txt': 'user material: preserve\n',
            '.gitignore': '/.eyr-plans/\n__pycache__/\n',
            'Makefile': '.PHONY: lint check restow verify\nlint check restow verify:\n\t@python3 -B -m unittest -q\n',
        }
        for path, text in files.items():
            (repo / path).write_text(text)
        command(['git', 'add', '--', *files], repo, env)
        command(['git', 'commit', '-qm', 'fixture seed'], repo, env)
        head = command(['git', 'rev-parse', 'HEAD'], repo, env).strip()
        index = (repo / '.git/index').read_bytes()
        before = {path: hashlib.sha256((repo / path).read_bytes()).hexdigest() for path in files}
        stream = repo / '.eyr-plans/live'
        if name == 'pause-cleanup':
            stream.mkdir(parents=True, mode=0o700)
            (stream / 'checkpoint.md').write_text('# Calculator workstream\n\nGoal: repair total and pause for H. No Git preparation.\nArtifacts: live-evidence.md remains needed; obsolete.md is an obsolete agent draft; user-note.md belongs to H.\nNext: implement, verify, remove only obsolete owned material, and retain resumable state.\n')
            for leaf in ('obsolete.md', 'live-evidence.md', 'user-note.md'):
                (stream / leaf).write_text(leaf + '\n')
        prompt = ('Act as primary on this substantive repository task, following the configured global workflow. '
                  'All implementation and Git operations must stay in this disposable repository; do not modify any other project or host configuration. '
                  + request)
        started = time.monotonic()
        output, stderr, returncode, timed_out = run_client(
            [args.opencode, 'run', '--format', 'json', '--dir', str(repo), prompt], repo, env, args.timeout)
        events = []
        for line in output.splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if isinstance(event, dict):
                events.append(event)
        loaded = False
        text = []
        for event in events:
            part = event.get('part', {})
            if not isinstance(part, dict):
                continue
            if event.get('type') == 'text':
                text.append(str(part.get('text', '')))
            if event.get('type') == 'tool_use':
                state = part.get('state', {})
                if not isinstance(state, dict):
                    continue
                inputs = state.get('input', {})
                if state.get('status') == 'completed' and isinstance(inputs, dict):
                    loaded |= part.get('tool') == 'skill' and inputs.get('name') == 'develop'
                    loaded |= part.get('tool') == 'read' and str(inputs.get('filePath', '')).endswith('/develop/SKILL.md')
                if part.get('tool') == 'question':
                    text.append(json.dumps(inputs))
        response = '\n'.join(text).lower()
        checks = {'client': returncode == 0 and not timed_out, 'develop_loaded': loaded,
                  'head_preserved': command(['git', 'rev-parse', 'HEAD'], repo, env).strip() == head,
                  'user_file_preserved': (repo / 'USER.txt').read_text() == files['USER.txt']}
        if name == 'plan':
            checks['source_preserved'] = all(hashlib.sha256((repo / path).read_bytes()).hexdigest() == digest for path, digest in before.items())
            checks['index_preserved'] = (repo / '.git/index').read_bytes() == index
            checks['no_preparation_choice'] = 'prepare commit reviews' not in response
        else:
            checks.update(repair_checks(repo, env))
            if name == 'handoff':
                checks['preparation_choice'] = 'prepare commit reviews' in response and 'pause here' in response
                checks['index_preserved'] = (repo / '.git/index').read_bytes() == index
            elif name == 'pause-cleanup':
                checks.update(obsolete_removed=not (stream / 'obsolete.md').exists(),
                              live_evidence_kept=(stream / 'live-evidence.md').exists(),
                               user_note_kept=(stream / 'user-note.md').exists(),
                               resume_state_kept=(stream / 'checkpoint.md').exists(),
                               index_preserved=(repo / '.git/index').read_bytes() == index,
                               no_preparation_choice='prepare commit reviews' not in response)
            else:
                checks['staged_repair'] = 'calc.py' in command(['git', 'diff', '--cached', '--name-only'], repo, env).splitlines()
                checks['no_repeated_preparation_choice'] = 'prepare commit reviews' not in response
                checks['candidate_review'] = 'commit and resume' in response and 'commit and pause' in response
        failed = [key for key, passed in checks.items() if not passed]
        print(json.dumps({'case': name, 'checks': checks, 'timed_out': timed_out,
                          'seconds': round(time.monotonic() - started, 1),
                          'tool_events': sum(event.get('type') == 'tool_use' for event in events)}, sort_keys=True), flush=True)
        if failed:
            failures.append(name + ': ' + ', '.join(failed))
            print(json.dumps({'case': name, 'diagnostic': diagnostic('\n'.join(text) + '\n' + stderr)}, sort_keys=True), flush=True)
    if failures:
        print('Unverified/failed behavior: ' + '; '.join(failures))
        print('Owned fixture retained: ' + str(root))
        return 1
    # Ready model-created records need primary inspection and exact-ID disposal.
    # Passing assertions are not a receipt rejection or authority to sweep them.
    if args.case in (None, 'prepare') or list(root.glob('*/.eyr-plans/governance')) or list(root.glob('*-records')):
        print('Owned fixture retained for primary receipt inspection/close-out: ' + str(root))
    else:
        shutil.rmtree(root)
    print('ok: selected develop behavior checks (bounded OpenCode observation)')
    return 0


if __name__ == '__main__':
    def interrupted(signum, _frame):
        sys.exit(128 + signum)
    for kind in SIGNALS:
        signal.signal(kind, interrupted)
    raise SystemExit(main())
