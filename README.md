# Multi-Vth-Cell-Swap
TCL script for post-synthesis leakage power minimization using multiple cell libraries [LVT (Low), SVT (Standard), HVT (High)]. Starting circuit netlist is composed of all LVT cells.

## Description
The function to perform cell swapping can be invoked as `multiVth slackThreshold maxPaths`, its arguemnts being:
- `slackThreshold`: Timing paths with slack < slackThreshold are defined as **violating paths**. Allowed
values may range from 0 to 0.25 ns.
- `maxPaths`: Maximum number of violating paths for each endpoint in the circuit. Allowed values may range
from 1 to 10000.

Example usage: `multiVth 0.10 100`

## Constraints
The following additional constraints are imposed:
- Worst slack must be positive.
- For each endpoint of the circuit, the number of violating paths must be < `maxPaths`.
- Logic gates must keep the same cell footprint (i.e. same strength), during the optimization loop.
- Run time (measured using the TCL clock command on the remote server) must be < 5 minutes.

## Project Structure:
- `BasicSwap.tcl`: Basic algorithm which:
  - (1) ranks cells in the circuit netlist based on descending slack;
  - (2) replaces the top 50% LVT (highest slack) cells with HVT cells;
  - (3) replaces the remaining 25% LVT cells with SVT cells.
- `OptimizedSwap.tcl`: More advanced algorithm which:
  - (1) ranks cells in the circuit netlist based on descending slack;
  - (2) swap highest slack cells to HVT, and if doing so introduces a timing violation, the cell is reverted to its original type;
  - (3) for cells which were reverted, try swapping to SVT, and if introducing a timing violation, revert back.
- `SYN Contest.pdf`: Report containing both algorithm's results, which were able to save at least 60% leakage power in both benchmarks (`c1908` and `c5315`).

More details can be found in the report `SYN Contest.tcl`.

## License
This project is licensed under the MIT License - see the LICENSE file for details.