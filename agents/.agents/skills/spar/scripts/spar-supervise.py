#!/usr/bin/env python3
"""spar-supervise.py - run one reviewer client under a hard timeout and stop every descendant.

Usage: spar-supervise.py SECONDS DIR -- COMMAND [ARG...]

Runs COMMAND in DIR in its own session, with stdin, stdout and stderr passed through. The
supervisor is a child subreaper, so descendants that start their own session, as OpenCode's
shell tool does, are adopted and stopped with the rest when the client exits, times out or
the supervisor is signalled. Exit: the client's status; 124 after the timeout; 128+N when
signalled; 125 when the end of every descendant cannot be confirmed; 64 on usage.
"""
import ctypes
import os
import signal
import subprocess
import sys
import time

PR_SET_CHILD_SUBREAPER = 36


def reap(leader):
    """Reap exited children; True once none remain (ECHILD), so no descendant survives."""
    while True:
        try:
            pid, status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return True
        if pid == 0:
            return False
        if pid == leader.pid:
            leader.returncode = os.waitstatus_to_exitcode(status)


def stop(leader):
    for kind in (signal.SIGTERM, signal.SIGKILL):
        if leader.returncode is None:
            try:
                os.killpg(leader.pid, kind)  # The unreaped leader still reserves its group ID.
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if reap(leader):
                return True
            # Only this supervisor's own unreaped children: no PID reuse, no foreign processes.
            listing = subprocess.run(["ps", "--ppid", str(os.getpid()), "-o", "pid="],
                                     capture_output=True, text=True, timeout=5, check=False)
            for text in listing.stdout.split():
                try:
                    os.kill(int(text), kind)
                except ProcessLookupError:
                    pass
            time.sleep(0.05)
    return reap(leader)


def main():
    args = sys.argv[1:]
    if len(args) < 4 or args[2] != "--" or not args[0].isdigit() or int(args[0]) < 1:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 64
    seconds, cwd, argv = int(args[0]), args[1], args[3:]
    signalled = []
    for kind in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(kind, lambda signum, _frame: signalled.append(signum))
    if ctypes.CDLL(None, use_errno=True).prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) != 0:
        print("SPAR-BRIDGE ERROR: cannot adopt the reviewer's descendants", file=sys.stderr)
        return 125
    leader = subprocess.Popen(argv, cwd=cwd, start_new_session=True)
    deadline = time.monotonic() + seconds
    status = None
    while status is None:
        if signalled:
            status = 128 + signalled[0]
        elif time.monotonic() >= deadline:
            status = 124
        else:
            event = os.waitid(os.P_PID, leader.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            if event is not None:
                status = event.si_status if event.si_code == os.CLD_EXITED else 128 + event.si_status
            else:
                time.sleep(0.05)
    if not stop(leader):
        print("SPAR-BRIDGE ERROR: the reviewer's processes could not all be stopped", file=sys.stderr)
        return 125
    return status


if __name__ == "__main__":
    sys.exit(main())
