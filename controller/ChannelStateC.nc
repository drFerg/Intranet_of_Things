/*
* author Fergus William Leahy
*/
#include "ChannelState.h"

module ChannelStateC {
	provides interface ChannelState;
}
implementation{
	command void ChannelState.init_state(ChannelState *state, uint8_t chan_num){
		state->chan_num = chan_num;
		state->seqno = 0;
		state->remote_addr = 0;
		state->ticks_till_ping = 0;
	}
}