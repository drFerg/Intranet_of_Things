/*
* author Fergus William Leahy
*/
#ifndef KNOT_CHANNEL_STATE_H
#define KNOT_CHANNEL_STATE_H

#include "KNoTProtocol.h"

/* Connection states */
#define STATE_IDLE       0
#define STATE_QUERY      1
#define STATE_QACKED     2
#define STATE_CONNECT    3
#define STATE_CONNECTED  4
#define STATE_DCONNECTED 5
#define STATE_PING       7
#define STATE_COMMANDED  9

/* Sets the channel state to the specified state */
#define set_state(chanstate, status) chanstate->state = status

/* Returns 1 if a channel is waiting for a reply message, 0 otherwise */
#define in_waiting_state(chanstate) (chanstate->state % 2 != 0)

typedef struct channel_state{
   uint8_t remote_addr; //Holds address of remote device
   uint8_t state;
   uint8_t seqno;
   uint8_t chan_num;
   uint8_t remote_chan_num;
   uint8_t ticks;
   uint8_t ticks_left;
   uint16_t rate;
   uint8_t ticks_till_ping;
   uint8_t attempts_left;
   uint8_t timer;
   DataPayload packet;
}ChannelState;





#endif /* KNOT_CHANNEL_STATE_H */