# Ibex Wishbone Adapter

Ibex Wishbone adapter handles the Ibex memory and a Wishbone B3 interfaces. This implementation went 5 steps:

1) Only classic Wishbone transfers possible
2) Bursts possible but using pre-defined length and two interlocked FSMs - latency increased.
3) Atttempt to have a moving window between the two FSMs while maximum 