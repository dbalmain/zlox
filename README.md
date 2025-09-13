# zlox - A Lox Interpreter in Zig

A complete implementation of the Lox programming language from Robert Nystrom's [Crafting Interpreters](http://craftinginterpreters.com/), written in Zig.

## Project Goals

This project was undertaken with two primary learning objectives:
1. Understanding interpreter design and implementation through the excellent Crafting Interpreters book
2. Learning the Zig programming language, partly motivated by discovering that the [Roc language](https://www.roc-lang.org/) was being re-implemented in Zig

## Building and Running

```bash
# Build the interpreter (debug mode)
zig build

# Build optimized version
zig build -Doptimize=ReleaseFast

# Run a Lox file
./zig-out/bin/zlox script.lox

# Run the benchmark
./zig-out/bin/zlox bench.lox

# Enable debugging features
zig build -Dtrace=true          # Enable execution tracing
zig build -Dgc_stress=true      # Stress test garbage collector
zig build -Dgc_log=true         # Log garbage collection activity
```

## Zig Impressions

Zig proved to be an excellent language for this project. The memory management tools made it relatively straightforward to eliminate the typical memory issues encountered in C development. It is different enough from C (especially as our implementations diverged) that I still had to think carefully about the implementation and understand what I was building.

While I appreciated the greater freedom Zig offers compared to Rust, I did occasionally miss Rust's static safety checking capabilities. Furthmore, reasoning about the performance of zig turned out to be much harder than I expected. Like Rust, Zig appears to require a solid investment in time to gain expertice and reap the benefits it offers.

## Project Structure

This project follows the book's chapter progression starting from Chapter 14 (the beginning of the C/bytecode implementation), with each chapter tagged for easy navigation:
- Chapters are tagged with version numbers starting from `v0.14.0`
- Challenges and minor improvements are tagged with patch versions (e.g., `v0.14.1`, `v0.15.1`)
- The final implementation will be tagged as `v1.0.0`
- All tests pass consistently across implementations
- I didn't start running the Nystrom's test suite on my code until chapter 24. Earlier chapters may have had subtle bugs and the error messages didn't 100% match.

You can explore the development history by checking out different tags to see the interpreter evolve from a simple bytecode foundation to the sophisticated final VM with classes, inheritance, and optimisations.

## Performance Analysis

I am disappointed that the Zig implementation performed significantly slower than the original C version, despite implementing several optimisations I hoped would improve efficiency:
- Interning all identifiers in a separate HashMap to avoid managing them on the interpreter's object heap
- Various other micro-optimisations like implementing `And` and `Or` op-codes.

Using the `bench.lox` code from [Faster Hash Table Probing](https://craftinginterpreters.com/optimization.html#faster-hash-table-probing) I found that my zig version was taking around 6000ms vs 2500ms for Nystron's C VM. I was able to get this down to under 5000ms with some minor tweaks documented below. I think I'd to start looking at the assembly code to get it in the same ballpark as the C code, something I don't have time for right now.

### Profiling and Investigation

I used standard Linux performance analysis tools to investigate the performance gap:

```bash
# Record performance data
perf record -g --call-graph=dwarf ./zig-out/bin/zlox bench.lox

# Generate performance report
perf report --stdio > perf_report.txt

# Create flamegraph for visual analysis
perf script | stackcollapse-perf.pl | flamegraph.pl > zlox_profile.svg
```

The profiling revealed that the C version kept ~85% of execution inlined in the main VM loop, while the Zig version fragmented execution across many function calls (~35% main loop + 49% scattered across functions). There are some good reasons for the difference in architecture and some not so good reasons.

1. I try to avoid using global variables as a general principal. However, Nystrom uses them to good effect to reduce the data that needs to be passed between function calls. There is only ever one VM created. Having to pass this vm pointer through each function is somewhat costly. I did experiment with switching to an implementation closer to that in the book with a global VM pointer but it didn't have a huge effect. The small improvement wasn't worth the extra effort it would have take to tidy up the code so I abandoned that change.
2. Many of zigs standard library functions return and OutOfMemory error which floated up through most of the functions in the VM. The C version simply exits when it is out of memory. Again, I experimented with exiting early for every such error, but it didn't seem to have much effect either. Zig seems to do an excellent job of optimising that error handling.
3. One of the early exercises was to allow for more than 256 contants. I added this early on and it ended up affecting a large number of instructions. This meant that many of the op-code handlers that were inlined in the C version were abstracted by functions to avoid duplication of code. But as I said in point 1 above, experiments with inlining these functions proved to be more effort than they were worth.


### Key Performance Discovery

Surprisingly, attempting to inline the hottest VM operations directly into the main dispatch loop provided minimal improvement and introduced complexity that we ultimately reverted.

The most significant performance improvement came from an counterintuitive discovery: **adding explicit runtime bounds checks actually improved performance by ~15-25%**. You can see this change in the final commit to v1.0.0. I've explicitly added a stack underflow check. My hypothesis is that without explicit bounds checks, Zig's compiler inserted expensive safety mechanisms (integer overflow detection, array bounds checking). I haven't looked deeply into this and I hope there is a better way around this issue because it would be nice to avoid those bounds checks altogether in a release build. As long as the compiler is correct, stack undeflow should not be possible. I'd rather just have a `std.debug.assert` to check during development.

I suspect there are lot of other optimisations like this I could use to make the Zig version as fast as the C version and if I was more invested in the Zig language, I'd invest the time to find them, but for now I think I'll return to Rust.

### Final Performance

After optimisations, the Zig implementation runs the book's benchmark in approximately 4.8 seconds compared to the C version's 2.4 seconds - a disappointing ~2x performance difference that I assume I could overcome with enough time.


## AI Use

I experimented early on with using Claude Code to write the code for me since I was completely unfamiliar with Zig. This turned out to be an interesting way to learn Zig but a poor way to learn what the book was teaching. And we got to a point at about chapter 24 where Claude had outrun itself and wasn't able to get the code working without a lot of help on my part. And because I hadn't been writing the code myself, I was finding it timeconsuming to debug the issues because I didn't understand the codebase as well as I should have.

I started again from scratch writing almost all of the code myself and using Claude code review and documentation (e.g. CHANGELOG and commit messages). Occsionally, I also used it to save time on large refactoring tasks.

Claude was also really helpful for doing the large-scale refactoring experiments to try to improve performance. Without Claude, I wouldn't have had the patience to do this myself and throwing away all of that effort when the experiment failed would have been very disheartening.

I'm finding AI more and more useful as I learn how to effectively use it. At the same time, I'm becoming more convinced that it's not going to be taking my job any time soon.

## Learning Outcomes

This project provided valuable insights into:
- Interpreter design and bytecode VM implementation
- Zig's memory management and safety features
- Performance profiling and optimisation techniques
- The sometimes counterintuitive relationship between safety and performance in systems programming languages

The journey from a simple tree-walk interpreter to an optimised bytecode VM was both educational and rewarding, despite the final performance not quite matching the original C implementation. I highly recommend Robert Nystrom's [Crafting Interpreters](http://craftinginterpreters.com/).
