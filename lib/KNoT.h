#ifndef KNOT_H
#define KNOT_H
/*Change include to suit lower layer network */
#include "KNoTProtocol.h"
#include "ChannelState.h"
/* Macro signifying payload of 0 length */
#define NO_PAYLOAD     0
 
/*
* the following definitions control the exponential backoff retry
* mechanism used in the protocol - these may also be changed using
* -D<symbol>=value in CFLAGS in the Makefile
*/
#define ATTEMPTS 7 /* number of attempts before setting state to TIMEDOUT */
#define TICKS 2 /* initial number of 20ms ticks before first retry
                 * number of ticks is doubled for each successive retry */
#define TICKS_TILL_PING (60 * 50) /* 60s * (50ms * 20ms) = 1 minute */
#define RSYN_RATE 15 /* Rate to send out a RSYN message */ 
/* Memsets a Datapayload */
#define clean_packet(dp) (memset(dp, '\0', sizeof(DataPayload)))

/* Sets a channels ticks to the specified amount, normally TICKS */
#define set_ticks(cstate, tick_count) do { cstate->ticks = tick_count; \
                                         cstate->ticks_left = tick_count; \
                                        } while (0)

#endif /* KNOT_H */