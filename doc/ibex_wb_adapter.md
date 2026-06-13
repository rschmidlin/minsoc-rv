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
   
## Following requirements for Wishbone to Ibex:
   
  This is a Wishbone to Ibex adapter and the Ibex interface behaves like a memory that responds to req_addr with one cycle delay. `req_valid` can only be asserted when the address is valid. Then, we have to wait one cycle until the data arrives, trigger wb_ack and next cycle present the new address. 

   (I) req_addr and req_valid shall have the same timing, one cycle after (wb_cyc&wb_stb)/wb_adr
   (II) resp_rdata arrives one cycle later matching resp_rdata timing
   (III) wb_ack is simply req_valid with a cycle delay

   
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
        
   | Signal | 0   | 1   | 2   | 3   | 4   | 5   | 6   | 7    | 8  | 9  |
   |--------+-----+-----+-----+-----+-----+-----+-----+------+----+----|
   | CYC    | 1   | 1   | 1   | 1   | 1   | 1   | 1   | 1    | 0  | 0  |
   | STB    | 1   | 1   | 1   | 0   | 1   | 1   | 1   | 1    | 0  | 0  |
   | ADR    | D0  | D0  | D1  | -   | D1  | D2  | D3  | D3   | DX | DX |
   | REQ    | D0  | D0  | D1  | -   | D1  | D2  | D3  | D3   | DX | DX |
   | GNT    | -   | D0  | -   | -   | D1  | D2  | D3  | -    | -  | -  |
   | RSP    |     |     | D0  | -   | -   | D1  | D2  | D3   | -  | -  |
   | ACK    | -   | -   | D0  | 0   | D1  | 0   | D2  | D3   | -  | -  |
   | CTI    | INC | INC | INC | INC | INC | INC | INC | STOP |    |    |

### Warnings:
      - unsupported != non-incremental
      - no late GNT after STB=0
      - CTI=111 needs lookahead or one-cycle delayed acceptance