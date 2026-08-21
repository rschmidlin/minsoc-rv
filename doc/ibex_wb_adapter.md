# Wishbone Ibex adapter

   Assumptions:

   (1) Memory will normally acknowledge continuously over bursts
   (2) Memory can still stall and add wait states by not acknowleding continuously - negate ACK
   (3) Wishbone master (host) can add wait states by negating STB

## Ibex interface
  
  Essentially, Ibex will signal a request over req_valid = 1 and corresponding req_add, req_we,
   and req_be. On gnt, either they switch immediately or req_valid is negated. Every granted 
   request must be acknowledged over resp_valid in order. On read requests, resp_rdata should
   be valid when resp_valid is signaled. While processing requests over Wishbone, write data
    must match the req_wdata of the corresponding gnt point in time. 
   
## Following requirements for Ibex to Wishbone:
   
   (a) Only acknowledge GNT if request can be stored for later execution
   (b) Only start WB after at least 1 request is available in storage
   (c) resp_valid can match wb_ack
   (d) When retrieving a request from storage, stop burst if request is not incremental (sequential address)
   (e) CTI must be set to 111 on last effective cycle, STB can be negated if request should be discarded

### Additional:
   1. Every resp_valid cycle must match a previous granted request
   2. Continue WB burst only while granted addresses are sequential
   
## Following requirements for Wishbone to Debug Memory

This adapter maps Wishbone accesses to the dm_top/dm_mem slave interface.
The downstream interface behaves as a local memory with fixed one-cycle
read latency.

A Wishbone access is translated into a one-cycle req_valid pulse.
The corresponding read data becomes available one cycle later.
wb_ack is asserted when the corresponding response data is available.

(I) req_addr and req_valid shall have the same timing and shall be asserted
    one cycle after acceptance of a Wishbone request (wb_cyc & wb_stb).

(II) resp_rdata shall correspond to the req_addr presented in the previous
     cycle.

(III) wb_ack shall be asserted one cycle after req_valid.

(IV) For read accesses, wb_dat_r shall be valid when wb_ack is asserted.

(V) For write accesses, wb_ack shall acknowledge completion of the
    corresponding req_valid request.

(VI) For burst accesses, the next req_addr shall only be generated after
     the previous access has been acknowledged.

   
## Ibex to Wishbone: 

 Control transactions on WB side. Can stall on Ibex side by delaying GNT
  or RSP. Can stall on WB side by negating STB.
   
   | Signal | 0  | 1  | 2  | 3   | 4   | 5   | 6   | 7   | 8    |  9 |
   |--------+----+----+----+-----+-----+-----+-----+-----+------+----|
   | REQ    | D0 | D0 | D1 | D2  | D2  | D3  | DX  | DX  | DX   | DX |
   | GNT    | -  | -  | D0 | D1  | -   | D2  | D3  | -   | -    |  - |
   | CYC    | 0  | 0  | 0  | 1   | 1   | 1   | 1   | 1   | 1    |  0 |
   | ACK    | -  | -  | -  | -   | D0  | D1  | 0   | D2  | D3   |  0 |
   | RSP    |    |    |    |     | D0  | D1  | -   | D2  | D3   |  0 |
   | CTI    |    |    |    | INC | INC | INC | INC | INC | STOP |    |

## Wishbone to Ibex: 

control transactions on Ibex side. Can stall on WB side by negating ACK. 
  Can stall on Ibex side by delaying REQ.
        
Cycle      N      N+1      N+2

WB STB     1       1
WB ADR     A0      A1

req_valid          1
req_addr           A0

resp_rdata                 D0
wb_ack                     1

req_valid                  1
req_addr                   A1

### Warnings:
      - unsupported != non-incremental
      - no late GNT after STB=0
      - CTI=111 needs lookahead or one-cycle delayed acceptance