#ifndef CHANNEL_TABLE
#define CHANNEL_TABLE

#include "ChannelState.h"
/* Num of channels available in table */
#ifndef CHANNEL_NUM
#define CHANNEL_NUM 5
#endif /* CHANNEL_NUM */

typedef struct knot_channel{
	ChanState state;
	struct knot_channel *nextChannel;
	uint8_t active;
}Channel;

#endif /* CHANNEL_TABLE */