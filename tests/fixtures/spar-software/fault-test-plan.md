# Replay regression test plan

Revision P1. This is a plan for review before execution. The path expressions below are data; no write implementation is supplied.

## Goal and constraints

Compare a repaired local inventory-reconstruction utility with its original version and a mutant that removes its path guard. Establish whether the regression tests detect writes outside the allocated reconstruction. The test's effects must stay inside a newly allocated, owned temporary directory `R`; no unrelated files are present there. Concurrent hostile modification is outside scope.

Each implementation is copied into `R` and run with working directory and `TMPDIR` set to `R`. No elevated privileges are used. The runner reports a failure if the command or assertions fail. The original and one mutant construct a destination as:

```python
Path(esp) / entry.removeprefix("/boot/")
```

The subsequent operation would create parents and open that destination for writing. The repaired version checks its boundary first. Assess each proposal below on its own; the plan has not selected one.

## Proposals

| Proposal | Layout and inputs | Observation |
| --- | --- | --- |
| A | `esp = R / "work" / "case" / "esp"`; inventory entry `/boot//probe` | Compare command status and inspect the reconstruction; fail on an unexpected result. |
| B | Same layout; pre-create the owned sentinel `R / "sentinel"`; inventory entry `"/boot/" + str(R / "sentinel")` | Check the sentinel's exact bytes after each run and report a boundary failure if changed. |
| C | Same layout; a relative-path generator emits at most seven `..` components followed by a file name, prefixed with `/boot/` | After each run inspect all of `R`, allowing its known infrastructure directories and reconstructed files only. |
| D | `esp = R / "p0" / "p1" / "p2" / "p3" / "p4" / "p5" / "p6" / "p7" / "esp"`; the same relative-path generator as C | Inspect all of `R` as in C, including writes outside `esp`. |

`R` is an absolute path. The generator in C and D emits no absolute remainder or other path syntax beyond the stated relative components and file name. Source copies, status checks and inspection are otherwise identical across proposals. Judge what each proposal can safely establish and identify any required change before execution.
