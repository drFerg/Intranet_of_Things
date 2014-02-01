#ifndef KNOT_H
#define KNOT_H
/*Change include to suit lower layer network */
#include "KNoTProtocol.h"
#include "ChannelState.h"

 
/*
* the following definitions control the exponential backoff retry
* mechanism used in the protocol - these may also be changed using
* -D<symbol>=value in CFLAGS in the Makefile
*/
#define TICK_RATE 100 /* tick rate in ms */
#define ATTEMPTS 5 /* number of attempts before removing channel */
#define TICKS 5 /* initial number of 20ms ticks before first retry
                 * number of ticks is doubled for each successive retry */
#define ticks_till_ping(send_rate)((3000 * send_rate)/TICK_RATE) /* rate\s * 3000ms / TICK_RATE= 3xrate = will ping after */
                               /* 3 packets have not been received. */
#define RSYN_RATE 15 /* Rate to send out a RSYN message */ 
/* Memsets a Datapayload */
#define clean_packet(dp) (memset(dp, '\0', sizeof(DataPayload)))

#endif /* KNOT_H */