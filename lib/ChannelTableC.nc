#include "ChannelTable.h"
#include "ChannelState.h"
#include <stdlib.h>

module ChannelTableC {
	provides {
		interface ChannelTable;
	}
}

implementation {
	static Channel channelTable[CHANNEL_NUM];
	static Channel *nextFree;
	static Channel *iterCurrent;
	static Channel *iterStart;
	uint8_t size;

	void init_state(ChanState *state, uint8_t chan_num){
		state->chan_num = chan_num;
		state->seqno = 0;
		state->remote_addr = 0;
		state->ticks_till_ping = 0;
	}
	/* 
	 * initialise the channel table 
	 */
	command void ChannelTable.init_table(){
		uint8_t i;
		size = 0;
		nextFree = channelTable;
		for (i = 0; i < CHANNEL_NUM; i++){
			channelTable[i].active = 0;
			channelTable[i].nextChannel = (struct knot_channel *)&(channelTable[(i+1) % CHANNEL_NUM]);
			init_state((&channelTable[i].state), i + 1);
		}
		channelTable[CHANNEL_NUM-1].nextChannel = NULL;
	}

	/*
	 * create a new channel if space available
	 * return channel num if successful, 0 otherwise
	 */
	command ChanState* ChannelTable.new_channel(){
		Channel *temp;
		if (size >= CHANNEL_NUM) return NULL;
		temp = nextFree;
		temp->active = 1;
		nextFree = temp->nextChannel;
		size++;
		if (iterStart) {
			temp->nextChannel = iterStart;
			iterStart = temp;
		}
		return &(temp->state);
	}

	/* 
	 * get the channel state for the given channel number
	 * return channel if successful, NULL otherwise
	 */
	command ChanState* ChannelTable.get_channel_state(int channel){
		if (channelTable[channel-1].active){
			return &(channelTable[channel-1].state);
		} else return NULL;
	}
	/*
	 * remove specified channel state from table
	 * (scrubs and frees space in table for a new channel)
	 */
	command void ChannelTable.remove_channel(int channel){
		Channel *next;
		Channel * chan = &(channelTable[channel-1]);
		chan->nextChannel = nextFree;
		init_state(&(chan->state), channel);
		chan->active = 0;
		nextFree = chan;
		size--;
		if (iterStart == chan){
			iterStart = chan->nextChannel;
		} else {
			next = iterStart;
			while (next){
				if (next->nextChannel == chan){
					next->nextChannel = chan->nextChannel;
					return;
				}
			}
		}
	}

	/* 
	 * destroys table 
	 */
	command void ChannelTable.destroy_table(){}
}