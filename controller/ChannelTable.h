#ifndef CHANNEL_TABLE
#define CHANNEL_TABLE

#include "ChannelState.h"
/* Num of channels available in table */
#define CHANNEL_NUM 5
typedef struct knot_channel{
	ChannelState state;
	struct knot_channel *nextChannel;
	uint8_t active;
}Channel;
#endif /* CHANNEL_TABLE */