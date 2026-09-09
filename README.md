# RV32I-Based Processor Core with INT8 Dot-Product Accelerators

Synthesizable Verilog implementations of a five-stage RISC-V processor and multiple INT8 dot-product accelerator architectures. This project compares accelerator folding strategies and processor-integration methods using a common 250 nm ASIC synthesis flow.

## Overview

The accelerator computes the dot product of two signed, eight-element INT8 vectors:

```text
result = sum(a[i] * b[i]), i = 0..7
```

Six standalone RTL configurations are provided to separate three design questions:

- **Processor baseline:** software multiplication on the base core versus a hardware `MUL` instruction.
- **Accelerator microarchitecture:** eight parallel multipliers, a four-multiplier folded datapath, or a fully folded one-multiplier MAC.
- **Integration method:** a Custom-0 instruction extension versus a memory-mapped I/O (MMIO) wrapper accessed with standard `lw`/`sw` instructions.

The primary PPA results in this README were obtained with Synopsys Design Compiler and a 250 nm standard-cell library. SKY130 was used only as a supplementary open-source cross-check.

## Processor architecture

The processor is a 32-bit, five-stage, in-order core organized as follows:

1. **IF:** instruction fetch and PC update
2. **ID:** decode, register-file read, and immediate generation
3. **EX:** ALU operation, branch comparison, and optional accelerator execution
4. **MEM:** load/store access
5. **WB:** register-file write-back

The implementation includes forwarding, load-use stall handling, and branch redirect/squash logic. Instruction and data memories use separate top-level interfaces. The design has one clock (`clk_i`) and an asynchronous active-low reset (`rst_ni`).

The RTL implements the integer ALU, six branch conditions, `JAL`/`JALR`, `LUI`/`AUIPC`, and the word load/store datapath used by the benchmark. It does not implement byte or halfword memory accesses, CSRs, traps, or interrupts, and it has not been validated with the official RISC-V compliance suite. It is therefore described here as RV32I-based rather than as a complete compliant implementation.

Configuration 2 adds the lower-32-bit `MUL` operation as a multiplication-enabled baseline. It is not an implementation of the complete RV32M extension.

## Design configurations

| # | Directory | Processor / accelerator | Integration | Multipliers | Folding factor | Compute pulses | Top module |
|---:|---|---|---|---:|---:|---:|---|
| 1 | `1_rv32i_base/` | Base processor | None | 0 | - | - | `core` |
| 2 | `2_rv32i_mul/` | Base processor + hardware `MUL` | Standard R-type `MUL` | 1 | - | - | `core` |
| 3 | `3_accel_8mul/` | Parallel dot-product accelerator | Custom-0 | 8 | 1 | 1 | `core` |
| 4 | `4_fold_4mul/` | Folded dot-product accelerator | Custom-0 | 4 | 2 | 2 | `core` |
| 5 | `5_mac_1mul/` | Fully folded MAC accelerator | Custom-0 | 1 | 8 | 8 | `core` |
| 6 | `6_mmio_8mul/` | Parallel dot-product accelerator | MMIO | 8 | 1 | 1 | `core_mmio_top` |

Each directory is a self-contained source snapshot. Select one directory, read all of its `.v` files, and use the top module listed above or in its `TOP.txt` file.

> **Important:** The checked-in configurations are already specialized. No external preprocessor defines are required. Do not mix RTL files from different configuration directories because several modules intentionally share the same names.

## Accelerator microarchitectures

Each accelerator stores two vectors in internal signed INT8 buffers. Four elements are packed into each 32-bit load word, with bits `[7:0]` mapped to the first element, so two transfers load each eight-element vector. The dot product is accumulated internally with 20-bit signed precision and returned as a signed 32-bit result.

### Eight-multiplier parallel architecture

The baseline accelerator evaluates all eight products in parallel and reduces them through a three-level balanced adder tree. Its main combinational path is:

```text
multiplier -> three-level adder tree
```

It has the lowest compute latency but the largest multiplier count.

### Four-multiplier folded architecture

Four multipliers are reused over two compute pulses. A one-bit fold index selects the lower or upper half of the vectors, and a partial-sum register accumulates the two halves. Its main combinational path is:

```text
input MUX -> multiplier -> two-level adder tree -> accumulator
```

The additional selection and accumulation logic reduces area but lengthens the critical path.

### One-multiplier MAC architecture

A single multiplier is reused over eight compute pulses. A three-bit fold index selects one vector element per pulse, and a partial-sum register performs serial accumulation. Its main combinational path is:

```text
input MUX -> multiplier -> accumulator
```

Removing the adder tree produces the smallest accelerator and makes the processor core critical again.

## Integration methods

### Custom-0 instruction extension

Configurations 3-5 instantiate the accelerator in the EX stage and use the RISC-V Custom-0 opcode (`0001011`).

| Instruction | `funct3` | Operation |
|---|---|---|
| `VLOAD_A_LO` | `000` | Load packed `a[0:3]` from `rs1` |
| `VLOAD_A_HI` | `001` | Load packed `a[4:7]` from `rs1` |
| `VLOAD_B_LO` | `010` | Load packed `b[0:3]` from `rs2` |
| `VLOAD_B_HI` | `011` | Load packed `b[4:7]` from `rs2` |
| `DOTPROD` | `100` | Advance the computation and return the current/final result through `rd` |

Software must issue `DOTPROD` once for the 8-multiplier design, twice for the 4-multiplier design, and eight times for the 1-multiplier design. There is no hardware busy/done handshake. For folded designs, intermediate compute instructions should target `x0`; only the final instruction should target the destination register. Custom instruction encodings require assembler/compiler support or explicit instruction encoding.

### Memory-mapped I/O

Configuration 6 places the eight-multiplier accelerator outside the processor core. `core_mmio_top` routes accesses in the `0xF000_00xx` region to `accel_mmio`; all other data-memory accesses remain connected to external DMEM.

The report specifies the 256-byte `0xF000_00xx` window. The current RTL implements these offsets:

| Address | Access | Register / action |
|---|---|---|
| `0xF000_0000` | Write | Load packed `a[0:3]` |
| `0xF000_0004` | Write | Load packed `a[4:7]` |
| `0xF000_0008` | Write | Load packed `b[0:3]` |
| `0xF000_000C` | Write | Load packed `b[4:7]` |
| `0xF000_0010` | Read | Read the latched result |
| `0xF000_0014` | Write | Trigger dot-product computation; write data is ignored |

This interface works with standard `lw`/`sw` instructions and avoids adding a custom opcode to the core. Its costs are extra address-decode/read-data-multiplexing logic and additional data-movement cycles.

## Top-level memory interface assumptions

All configurations expose the same instruction- and data-memory ports; configuration 6 adds only the internal MMIO routing through its wrapper.

- IMEM is expected to provide one-cycle synchronous reads.
- DMEM is configured for asynchronous/combinational reads.
- The interface has no ready/valid handshake and no byte-enable signals.
- The register file is a 32 x 32 flip-flop array with asynchronous reads and falling-edge writes; no SRAM or other memory macro is included.

## Using the RTL

For a syntax/elaboration check with Icarus Verilog, select one configuration and its corresponding top module. For example:

```sh
iverilog -g2012 -tnull -s core 3_accel_8mul/*.v
iverilog -g2012 -tnull -s core_mmio_top 6_mmio_8mul/*.v
```

For synthesis, read every `.v` file from exactly one configuration directory. A minimal Design Compiler source-loading example is:

```tcl
set cfg_dir ./3_accel_8mul
set top core

analyze -format verilog [glob ${cfg_dir}/*.v]
elaborate ${top}
current_design ${top}
link
check_design
```

Library setup, operating conditions, timing constraints, and power-activity assumptions must be supplied for the target technology. The snippet above demonstrates source loading only; it is not the complete flow used to produce the results below.

## Reported verification methodology

The accompanying study reports the following verification process:

- Icarus Verilog using `iverilog -g2012` and `vvp`.
- A nine-case regression across all six configurations.
- Correct dot-product output for every configuration; the documented workload produced the expected result of 40.
- End-to-end cycle counts that include operand loading, compute pulses, and processor-pipeline overhead.

The regression testbench and `run_regression.sh` referenced in the study are not included in this RTL snapshot, so those functional results cannot currently be reproduced from this repository alone. As a packaging check, all six source sets do elaborate successfully with Icarus Verilog 12.0.

## ASIC synthesis methodology

The primary synthesis study used:

- **Tool:** Synopsys Design Compiler Z-2007.03-SP4
- **Library:** `lec25dscc25_SS.db`
- **Technology corner:** 250 nm, Slow-Slow
- **Supply voltage:** 2.25 V
- **9.0 ns clock constraint:** used to expose critical-path differences; only the 4-multiplier design violated timing
- **9.4 ns clock constraint:** common timing-met point used for area and power comparison across all six configurations
- **Area metric:** Design Compiler `Total cell area`, not die/core physical area
- **Power metric:** internal + switching + leakage power estimated statistically without VCD annotation

The reported values are synthesis-level estimates, not post-layout measurements or fabricated-silicon measurements.

## 250 nm ASIC results

### End-to-end performance

| Configuration | Cycles | Speedup vs. base processor | Speedup vs. processor + `MUL` |
|---|---:|---:|---:|
| Base processor | 856 | 1.0x | 0.07x |
| Processor + `MUL` | 56 | 15.3x | 1.0x |
| 8-mul Custom-0 | 18 | 47.6x | 3.11x |
| 4-mul folded | 19 | 45.1x | 2.95x |
| 1-mul MAC | 25 | 34.2x | 2.24x |
| MMIO 8-mul | 21 | 40.8x | 2.67x |

The processor + `MUL` configuration is the fairer general-purpose baseline because the base implementation performs multiplication in software. Against that baseline, the parallel accelerator reduces the measured latency from 56 to 18 cycles.

At the common 9.4 ns clock constraint, approximately 106 MHz, the study reports the following operation rates and energy efficiencies using its stated operation-count convention:

| Configuration | Performance (MOPS) | Energy efficiency (GOPS/W) |
|---|---:|---:|
| Base processor | 1.98 | 0.07 |
| Processor + `MUL` | 30.3 | 1.02 |
| 8-mul Custom-0 | 94.2 | 2.72 |
| 4-mul folded | 89.3 | 2.85 |
| 1-mul MAC | 67.8 | 2.21 |
| MMIO 8-mul | 80.8 | 2.52 |

### Area at a 9.4 ns clock constraint

| Configuration | Total cell area (µm²) | Change vs. base processor |
|---|---:|---:|
| Base processor | 664,838 | Reference |
| Processor + `MUL` | 800,120 | +20.4% |
| 8-mul Custom-0 | 882,466 | +32.7% |
| 4-mul folded | 843,557 | +26.9% |
| 1-mul MAC | 745,318 | +12.1% |
| MMIO 8-mul | 914,400 | +37.5% |

Because the processor dominates total area, whole-design numbers understate the effect of folding. Subtracting the base processor area gives the following first-order estimate of accelerator-related area:

| Accelerator configuration | Estimated accelerator area (µm²) | Change vs. 8-mul |
|---|---:|---:|
| 8-mul Custom-0 | 217,628 | Reference |
| 4-mul folded | 178,719 | -17.9% |
| 1-mul MAC | 80,480 | -63.0% |
| MMIO 8-mul, including wrapper | 249,562 | +14.7% |

These values are subtraction-based estimates rather than hierarchical area reports.

### Power at a 9.4 ns clock constraint

| Configuration | Dynamic (mW) | Leakage (mW) | Total (mW) |
|---|---:|---:|---:|
| Base processor | 27.96 | 0.837 | 28.80 |
| Processor + `MUL` | 28.45 | 1.337 | 29.79 |
| 8-mul Custom-0 | 29.68 | 4.886 | 34.57 |
| 4-mul folded | 29.79 | 1.546 | 31.34 |
| 1-mul MAC | 29.80 | 0.915 | 30.72 |
| MMIO 8-mul | 29.98 | 2.132 | 32.11 |

Dynamic power remains close across the six configurations because the processor core dominates switching power under this estimation method. Folding has a larger effect on leakage: the one-multiplier design reduces measured leakage from 4.886 mW to 0.915 mW, approximately a 5.3x reduction relative to the eight-multiplier accelerator.

### Critical-path behavior at a 9.0 ns clock constraint

| Configuration | Reported critical path | Path location | Timing status |
|---|---:|---|---|
| Base processor | 8.65 ns | Core, forwarding to ALU add | MET |
| Processor + `MUL` | Full-cycle path below 9 ns | Core; RF half-cycle path reported at 4.15 ns | MET |
| 8-mul Custom-0 | 8.67 ns | Accelerator, multiplier to three-level tree | MET |
| 4-mul folded | 9.22 ns | Accelerator, MUX to multiplier to tree to accumulator | VIOLATED, reported slack -0.52 ns |
| 1-mul MAC | 8.66 ns | Core | MET |
| MMIO 8-mul | 8.65 ns | Core | MET |

The timing trend is non-monotonic. Reducing the multiplier count from eight to four adds an input MUX and an accumulator to the serial datapath, making the four-multiplier design slower despite its smaller area. Folding further to one multiplier removes the adder tree, so the processor core becomes critical again. All six configurations meet timing at the common 9.4 ns comparison point.

## Key findings

- The eight-multiplier Custom-0 accelerator achieved the lowest measured latency: 18 cycles, or 3.11x faster than the processor + `MUL` baseline.
- Folding from eight multipliers to one reduced the estimated accelerator-only area by 63% and leakage power by approximately 5.3x.
- Area decreases monotonically with more folding, but critical-path delay does not. The four-multiplier datapath was the only configuration to violate the 9.0 ns timing constraint, although it had the highest reported energy efficiency at the common 9.4 ns point.
- MMIO integration avoided a custom ISA extension with a measured overhead of three cycles and approximately 3.6% total cell area relative to the Custom-0 eight-multiplier configuration.

## Result scope and limitations

- Absolute area, delay, and power values are specific to the educational 250 nm library, synthesis version, constraints, and optimization behavior used in the study.
- Power was estimated without workload-derived VCD/SAIF activity. The values are most useful for comparisons within this experiment rather than as absolute workload power predictions.
- Accelerator-only area was estimated by subtracting the base processor area and therefore includes configuration-dependent integration logic.
- The results are synthesis-level estimates and do not include placement and routing, extracted interconnect, clock-tree synthesis, IR drop, or post-layout signoff.
- The performance experiment covers one eight-element dot-product kernel rather than a complete convolutional or fully connected neural-network workload.

## Supplementary SKY130 cross-check

A preliminary Yosys + SKY130 HD synthesis was used only as an open-source sanity check. It is not the primary PPA dataset, and values from different processes, libraries, constraints, and synthesis flows should not be expected to preserve identical absolute values or rankings.

## Related study

The architecture and measurements summarized here are based on the May 2026 study *Design and ASIC PPA Analysis of an INT8 8-element Dot-Product Accelerator for a RISC-V Processor*.
