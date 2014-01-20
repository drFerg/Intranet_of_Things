#include "ChannelState.h"
interface ChannelTable {
		/* 
	 * initialise the channel table 
	 */
	command void init_table();

	/*
	 * create a new channel if space available
	 * return channel if successful, NULL otherwise
	 */
	command ChanState * new_channel();

	/* 
	 * get the channel state for the given channel number
	 * return 1 if successful, 0 otherwise
	 */
	command ChanState * get_channel_state(int channel);

	/*
	 * remove specified channel state from table
	 * (scrubs and frees space in table for a new channel)
	 */
	command void remove_channel(int channel);

	/* 
	 * destroys table 
	 */
	command void destroy_table();
}