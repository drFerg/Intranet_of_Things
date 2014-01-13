interface KNoT{

	/* A helper function to fill in a DataPayload struct */
	command void dp_complete(DataPayload *dp, uint8_t src, uint8_t dst, 
             uint8_t cmd, uint8_t len);

	/* Checks the sequence number and returns 1 if in sequence, 0 otherwise */
	command int valid_seqno(ChanState *state, DataPayload *dp);

	/* Sends DataPayload on a KNoT channel specified in the state */
	command void send_on_chan(ChanState *state, DataPayload *dp);

	/* Sends a DataPayload as a broadcast transmission */
	command void knot_broadcast(ChanState *state, DataPayload *dp);

	/* Sends a ping packet to the channel in state */
	command void ping(ChanState *state);

	/* Handles the reception of a PING packet, replies with a PACK */
	command void ping_handler(ChanState *state, DataPayload *dp);

	/* Handles the reception of a PACK packet */
	command void pack_handler(ChanState *state, DataPayload *dp);

	/* Closes the channel specified and sends out a DISCONNECT packet */
	command void close_graceful(ChanState *state);

	/* Handles the reception of a DISCONNECT packet */
	command void close_handler(ChanState *state, DataPayload *dp);
}