"""Exercise live-runner cleanup and repair checks with owned synthetic clients."""
import json
import os
from pathlib import Path
import select
import runpy
import signal
import subprocess
import sys
import tempfile
import time
from unittest import mock


RUNNER = Path(__file__).with_name('develop-live.py').resolve()
with tempfile.TemporaryDirectory(prefix='develop-runner-fixture-') as temporary:
    base = Path(temporary)
    fake = base / 'client'
    fake.write_text('#!' + sys.executable + '\n' + r'''
import os, signal, subprocess, sys, time
from pathlib import Path
trace = Path(os.environ['DEVELOP_TEST_TRACE'])
signal.signal(signal.SIGTERM, signal.SIG_IGN)
child = subprocess.Popen([sys.executable, '-c', "import os,signal,time; from pathlib import Path; signal.signal(signal.SIGTERM,signal.SIG_IGN); Path(os.environ['DEVELOP_TEST_TRACE'], 'child').write_text(str(os.getpid())); time.sleep(60)"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
(trace / 'parent').write_text(str(os.getpid()))
while not (trace / 'release').exists(): time.sleep(0.02)
''')
    fake.chmod(0o700)
    for case in ('term', 'int', 'hup', 'timeout', 'normal-orphan'):
        trace = base / case
        trace.mkdir()
        home = trace / 'home'
        home.mkdir()
        env = {**os.environ, 'HOME': str(home), 'TMPDIR': str(trace), 'HISTFILE': '/dev/null',
               'DEVELOP_TEST_TRACE': str(trace), 'PYTHONDONTWRITEBYTECODE': '1'}
        for kind in ('CONFIG', 'DATA', 'CACHE', 'STATE', 'RUNTIME'):
            env['XDG_' + kind + ('_DIR' if kind == 'RUNTIME' else '_HOME')] = str(home / kind.lower())
        driver = subprocess.Popen([sys.executable, '-B', str(RUNNER), '--opencode', str(fake),
                                   '--case', 'plan', '--timeout', '2' if case == 'timeout' else '30'],
                                  env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                  start_new_session=True)
        handles = []
        try:
            for _ in range(200):
                if all((trace / leaf).exists() for leaf in ('parent', 'child')):
                    break
                assert driver.poll() is None, 'runner exited before synthetic-client readiness'
                time.sleep(0.02)
            assert all((trace / leaf).exists() for leaf in ('parent', 'child')), 'readiness timeout'
            handles = [os.pidfd_open(int((trace / leaf).read_text())) for leaf in ('parent', 'child')]
            if case == 'normal-orphan':
                (trace / 'release').touch()
            elif case != 'timeout':
                driver.send_signal({'term': signal.SIGTERM, 'int': signal.SIGINT, 'hup': signal.SIGHUP}[case])
            out, err = driver.communicate(timeout=15)
            expected = {'term': 143, 'int': 130, 'hup': 129}.get(case, 1)
            assert driver.returncode == expected, (case, driver.returncode, err)
            assert 'Owned fixture (retained until successful cleanup): ' in out, (case, out)
            fixtures = list(trace.glob('develop-live-*'))
            assert len(fixtures) == 1 and fixtures[0].is_dir(), 'failed/interrupted fixture was lost'
            if case == 'timeout':
                assert '"timed_out": true' in out, out
            assert all(select.select([handle], [], [], 2)[0] for handle in handles), (case, 'owned process survived')
        finally:
            if driver.poll() is None:
                driver.send_signal(signal.SIGTERM)
                try:
                    driver.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    driver.kill()
                    driver.wait(timeout=2)
            for handle in handles:
                if not select.select([handle], [], [], 0)[0]:
                    signal.pidfd_send_signal(handle, signal.SIGKILL)
                    assert select.select([handle], [], [], 2)[0], 'synthetic process rescue failed'
                os.close(handle)
    trace = base / 'exception'
    trace.mkdir()
    handles = []
    runtime = runpy.run_path(str(RUNNER))

    def broken_pipe(process, *args, **kwargs):
        if not handles:
            for _ in range(200):
                if (trace / 'child').exists():
                    break
                time.sleep(0.02)
            handles.extend(os.pidfd_open(int((trace / leaf).read_text())) for leaf in ('parent', 'child'))
        raise OSError('synthetic pipe failure')

    try:
        with mock.patch.object(subprocess.Popen, 'communicate', broken_pipe):
            runtime['run_client']([str(fake)], trace, {**env, 'DEVELOP_TEST_TRACE': str(trace)}, 30)
        raise AssertionError('synthetic communication failure was swallowed')
    except OSError as error:
        assert str(error) == 'synthetic pipe failure', str(error)
    finally:
        for handle in handles:
            ended = bool(select.select([handle], [], [], 2)[0])
            if not ended:
                signal.pidfd_send_signal(handle, signal.SIGKILL)
            os.close(handle)
            assert ended, 'communication exception stranded an owned process'
    repair_client = base / 'repair-client'
    repair_client.write_text('#!' + sys.executable + '\n' + r'''
import json, os
from pathlib import Path
plan = os.environ['DEVELOP_REPAIR_CASE'] == 'plan'
if not plan:
    Path('calc.py').write_text(os.environ['DEVELOP_CALC'])
    if os.environ['DEVELOP_TESTS'] == 'delete':
        Path('test_calc.py').unlink()
    else:
        Path('test_calc.py').write_text(os.environ['DEVELOP_TESTS'])
print(json.dumps({'type': 'tool_use', 'part': {'tool': 'skill', 'state': {
    'status': 'completed', 'input': {'name': 'develop'}}}}))
print(json.dumps({'type': 'text', 'part': {'text': 'Repair plan only.' if plan else
    'Prepare commit reviews or Pause here'}}))
''')
    repair_client.chmod(0o700)
    # Empty discovery exits 0 on older Python and 5 on Python 3.14+. The
    # independent oracle must reject broken code under either native result.
    empty_repo = base / 'empty-discovery'
    empty_repo.mkdir()
    _, _, empty_returncode, empty_timed_out = runtime['run_client'](
        [sys.executable, '-B', '-m', 'unittest', '-q'], empty_repo, env, 5)
    assert not empty_timed_out and empty_returncode in (0, 5), empty_returncode
    empty_tests_passed = empty_returncode == 0
    correct = 'def total(values):\n    return sum(values)\n'
    broken = 'def total(values):\n    return 0\n'
    ordinary_tests = '''import unittest
from calc import total
class Tests(unittest.TestCase):
    def test_total(self):
        self.assertEqual(total([17, 25]), 42)
        self.assertEqual(total([]), 0)
'''
    weakened_tests = ordinary_tests.replace('total([17, 25]), 42', 'total([17, 25]), 0')
    scenarios = (
        ('plan', broken, ordinary_tests, None, None),
        ('correct', correct, ordinary_tests, True, True),
        ('broken-deleted-tests', broken, 'delete', empty_tests_passed, False),
        ('broken-empty-tests', broken, '', empty_tests_passed, False),
        ('broken-weakened-tests', broken, weakened_tests, True, False),
        ('empty-wrong', 'def total(values):\n    return sum(values) if values else 1\n', '', empty_tests_passed, False),
        ('negatives-wrong', 'def total(values):\n    return sum(v for v in values if v > 0)\n', ordinary_tests, True, False),
        ('multiple-wrong', 'def total(values):\n    return sum(values[:2])\n', ordinary_tests, True, False),
        ('stateful-wrong', 'answer = 0\ndef total(values):\n    global answer\n    answer += sum(values)\n    return answer\n', '', empty_tests_passed, False),
        ('exit-zero-import', 'raise SystemExit(0)\n' + correct, '', empty_tests_passed, False),
        ('os-exit-zero-import', 'import os\nos._exit(0)\n' + correct, '', empty_tests_passed, False),
        ('exit-zero-midway', 'import os\ndef total(values):\n    if not values:\n        os._exit(0)\n    return sum(values)\n', ordinary_tests, True, False),
        ('correct-failing-tests', correct, weakened_tests, False, True),
    )
    for name, source, tests, tests_passed, oracle_passed in scenarios:
        trace = base / name
        trace.mkdir()
        home = trace / 'home'
        home.mkdir()
        repair_env = {**env, 'HOME': str(home), 'TMPDIR': str(trace),
                      'DEVELOP_REPAIR_CASE': name, 'DEVELOP_CALC': source, 'DEVELOP_TESTS': tests}
        for kind in ('CONFIG', 'DATA', 'CACHE', 'STATE', 'RUNTIME'):
            repair_env['XDG_' + kind + ('_DIR' if kind == 'RUNTIME' else '_HOME')] = str(home / kind.lower())
        out, err, returncode, timed_out = runtime['run_client'](
            [sys.executable, '-B', str(RUNNER), '--opencode', str(repair_client),
             '--case', 'plan' if name == 'plan' else 'handoff', '--timeout', '5'],
            trace, repair_env, 15)
        passed = name == 'plan' or (tests_passed and oracle_passed)
        assert not timed_out and returncode == (0 if passed else 1), (name, returncode, out, err)
        assessments = [json.loads(line) for line in out.splitlines() if line.startswith('{')]
        checks = next(item['checks'] for item in assessments if 'checks' in item)
        if name == 'plan':
            assert all(checks.values()), checks
            assert 'repair_verified' not in checks and 'total_oracle_passed' not in checks, checks
        else:
            assert checks['unittest_passed'] is tests_passed, (name, checks)
            assert checks['total_oracle_passed'] is oracle_passed, (name, checks)
            assert checks['repair_verified'] is passed, (name, checks)
            assert all(value for key, value in checks.items() if key not in (
                'unittest_passed', 'total_oracle_passed', 'repair_verified')), (name, checks)
        fixtures = list(trace.glob('develop-live-*'))
        assert len(fixtures) == (0 if passed else 1), (name, 'fixture retention mismatch', out)
        if name.startswith('broken-'):
            assert (fixtures[0] / 'handoff/calc.py').read_text() == broken, name

    # Bound an oracle that never reaches completion, using the same process
    # cleanup exercised above. No client-edited tests discover this module.
    trace = base / 'oracle-timeout'
    trace.mkdir()
    (trace / 'calc.py').write_text('import signal, time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\ntime.sleep(60)\n' + correct)
    started = time.monotonic()
    checks = runtime['repair_checks'](trace, repair_env, timeout=0.5)
    assert checks == {'unittest_passed': empty_tests_passed, 'total_oracle_passed': False, 'repair_verified': False}, checks
    assert time.monotonic() - started < 8, 'oracle termination exceeded its cleanup bound'
    # These fixtures contain no governance records and no live client state.
print('ok: develop runner bounds TERM/INT/HUP, timeout, exceptions and normal-exit descendants; failed fixtures retained by runner')
print('ok: 13 synthetic behavior cases cover independent totals, test tampering, early zero exits, ordinary-test failures and mutation-free planning; oracle timeout bounded')
