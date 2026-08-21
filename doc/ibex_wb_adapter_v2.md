# Ibex Wishbone Adapter

Ibex Wishbone adapter handles the Ibex memory and a Wishbone B3 interfaces. This implementation went 5 steps:

| Variant                 | Main idea                                         | Strength                    | Weakness                        | Branch            | 
| ----------------------- | ------------------------------------------------- | --------------------------- | ------------------------------- |-------------------|
| Direct FSM              | no real queue, state-driven translation           | small                       | fragile around redirects/bursts | wishbone-burst    |
| Window/counter FSM      | accepted/transferred window tracking              | efficient                   | hard invariants                 | wishbone-burst-b2_working |
| FIFO with Ibex-side FSM | FSM accepts from Ibex, then writes FIFO           | controlled, easier to stage | two control layers              | wishbone-burst-b3 |
| FIFO directly on Ibex   | `req && gnt` pushes FIFO                          | clean OBI invariant         | WB side needs lookahead         | wishbone-burst-b4 |
| FIFO + preload buffer   | direct FIFO plus explicit `slot0/slot1` lookahead | cleanest separation         | slightly more local buffering   | wishbone-burst-b5 |

| Variant                 | Performance               | Stability | Determinism                    | Release suitability         |
| ----------------------- | ------------------------- | --------- | ------------------------------ | --------------------------- |
| Direct FSM              | potentially low latency   | weak      | weak around redirects/bursts   | no                          |
| Window/counter FSM      | probably fastest/smallest | fragile   | hard invariants                | no                          |
| FIFO with Ibex-side FSM | decent                    | better    | medium, but two control layers | maybe educational           |
| FIFO directly on Ibex   | good                      | good      | clean OBI boundary             | good, but lookahead awkward |
| FIFO + preload buffer   | good to very good         | best      | best                           | yes                         |