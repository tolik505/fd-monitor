# fd-monitor

`fd-monitor` is a terminal tool for macOS that tracks open file descriptors (FDs) across all processes.

It continuously samples process FD counts, then renders:
- total FD usage over time (ASCII graph)
- number of inaccessible PIDs (permission-limited processes)
- top processes by open FD count

## Why this tool

Use it to quickly spot FD growth and find processes that are consuming the most file descriptors.

## Requirements

- macOS (the sampler uses `libproc` APIs)
- Zig compiler

## Run

From the project root:

```bash
zig run main.zig --
```

Run with options:

```bash
zig run main.zig -- --interval-ms=250 --history-points=180 --top=30
```

Build a binary:

```bash
zig build-exe main.zig
./main
```

## CLI flags

- `--interval-ms=<N>`: refresh interval in milliseconds (default: `500`)
- `--history-points=<N>`: number of points kept in the graph (default: `120`)
- `--top=<N>`: number of processes shown in the table (default: `20`)
- `--no-color`: disable ANSI reset/color handling
- `--help`: print usage

`N` must be a positive integer (`> 0`).

## Output overview

Each refresh prints:
- header with timestamp, total FDs, and inaccessible PID count
- 10-row ASCII graph of recent total FD values
- table of top processes (`PID`, `FD_COUNT`, `%`, `NAME`)
- aggregated `others` row when more processes exist than `--top`

Stop with `Ctrl-C`.

## Sample output

```text
fd-monitor  |  ts=1772966458123  total_fds=14320  inaccessible_pids=18
Graph (20 points, min=14102, max=14320, current=14320)
    5496 |            #     #########
    5494 |             #             #
    5492 |############     #                   #
    5490 |                              #
    5488 |                             #
    5486 |              # #           #  ######
    5484 |               #
    5482 |
    5480 |
    5479 |                                      #########
         +-----------------------------------------------

Top processes by open file descriptors
PID      FD_COUNT   PCT     NAME
-------------------------------------------
712      1180       8.24%  Chrome
498      911        6.36%  Code
301      734        5.12%  Dropbox
84       511        3.56%  launchd
1        402        2.80%  kernel_task
others   10582      73.89%  (312 processes)

Press Ctrl-C to exit.
```

## Tests

Run all tests:

```bash
zig test all_tests.zig
```
