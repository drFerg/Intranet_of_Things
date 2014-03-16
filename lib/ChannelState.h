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
#define STATE_RSYN       10
#define STATE_RACK_WAIT  11
#define STATE_ASYM_QUERY 12
#define STATE_ASYM_RESP  13
#define STATE_ASYM_RESP_ACK 14
#define STATE_ASYM_REQ_KEY 15
/* Sets the channel state to the specified state */
#define set_state(chanstate, status) chanstate->state = status

/* Returns 1 if a channel is waiting for a reply message, 0 otherwise */
#define in_waiting_state(chanstate) (chanstate->state % 2 != 0)
#define ticks_left(chanstate) (chanstate->ticks_left > 0)
#define attempts_left(chanstate) (chanstate->attempts_left > 0)

/* Sets a channels ticks to the specified amount, normally TICKS */
#define set_ticks(chanstate, tick_count) do { chanstate->ticks = tick_count; \
                                              chanstate->ticks_left = tick_count; \
                                        } while (0)
#define set_attempts(chanstate, tries) (chanstate->attempts_left = tries)
#define decrement_ticks(chanstate) (chanstate->ticks_left--)
#define decrement_attempts(chanstate)(chanstate->attempts_left--)

typedef struct channel_state{
   uint8_t remote_addr; //Holds address of remote device
   uint8_t state;
   uint8_t seqno;
   uint8_t chan_num;
   uint8_t remote_chan_num;
   uint16_t rate;
   uint8_t ticks;
   uint8_t ticks_left;
   uint8_t ticks_till_ping;
   uint8_t attempts_left;
   uint8_t key[SYM_KEY_SIZE];
   uint8_t packet[MAX_PACKET_SIZE];
}ChanState;





#endif /* KNOT_CHANNEL_STATE_H */