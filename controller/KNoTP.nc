#include <stdlib.h>
#include "KNoT.h"
#if DEBUG
#include "printf.h"
#define PRINTF(...) printf(__VA_ARGS__)
#define PRINTFFLUSH(...) printfflush()
#elif SIM
#define PRINTF(...) dbg("DEBUG",__VA_ARGS__)
#define PRINTFFLUSH(...)
#else  
#define PRINTF(...)
#define PRINTFFLUSH(...)
#endif

#define SEQNO_START 0
#define SEQNO_LIMIT 255

module KNoTP @safe() {
	provides interface KNoT;
	uses {
		interface Boot;
        interface AMPacket;
        interface AMSend;
        interface SplitControl as RadioControl;
	}
}
implementation {
	message_t am_pkt;
	bool sendBusy = FALSE;


	void increment_seq_no(ChanState *state, DataPayload *dp){
		if (state->seqno >= SEQNO_LIMIT){
			state->seqno = SEQNO_START;
		} else {
			state->seqno++;
		}
		dp->hdr.seqno = state->seqno;
	}
	
	void send(int dest, DataPayload *dp){
		uint8_t len = sizeof(PayloadHeader) + sizeof(DataHeader) + dp->dhdr.tlen;
		DataPayload *payload = (DataPayload *) (call AMSend.getPayload(&am_pkt, sizeof(DataPayload)));
		memcpy(payload, dp, sizeof(DataPayload));
		if (call AMSend.send(dest, &am_pkt, len) == SUCCESS) sendBusy = TRUE;
		else {
			PRINTF("ID: %d, Radio Msg could not be sent, channel busy\n", TOS_NODE_ID);
			//report_problem();
		}
	}

	command void KNoT.dp_complete(DataPayload *dp, uint8_t src, uint8_t dst, 
	             uint8_t cmd, uint8_t len){
		dp->hdr.src_chan_num = src; 
		dp->hdr.dst_chan_num = dst; 
		dp->hdr.cmd = cmd; 
		dp->dhdr.tlen = len;
	}

	command int KNoT.valid_seqno(ChanState *state, DataPayload *dp){
		if (state->seqno > dp->hdr.seqno){ // Old packet or sender confused
			return 0;
		} else {
			state->seqno = dp->hdr.seqno;
			if (state->seqno >= SEQNO_LIMIT){
				state->seqno = SEQNO_START;
			}
			return 1;
		}
	}

	command void KNoT.send_on_chan(ChanState *state, DataPayload *dp){
		increment_seq_no(state, dp);
		send(state->remote_addr, dp);
	}

	command void KNoT.knot_broadcast(ChanState *state, DataPayload *dp){
		increment_seq_no(state, dp);
		send(AM_BROADCAST_ADDR, dp);
	}

	command void KNoT.ping(ChanState *state){
		DataPayload *new_dp = &(state->packet);
		clean_packet(new_dp);
		call KNoT.dp_complete(new_dp, state->chan_num, state->remote_chan_num, 
		           PING, NO_PAYLOAD);
		call KNoT.send_on_chan(state, new_dp);
		state->state = STATE_PING;
	}

	command void KNoT.pack_handler(ChanState *state, DataPayload *dp){
		if (state->state != STATE_PING) {
			PRINTF("Not in PING state\n");
			return;
		}
		state->state = STATE_CONNECTED;

	}

	command void KNoT.ping_handler(ChanState *state, DataPayload *dp){
		DataPayload *new_dp;
		if (state->state != STATE_CONNECTED) {
			PRINTF("Not in Connected state\n");
			return;
		}
		PRINTF("PINGing back\n");
		new_dp = &(state->packet);
		clean_packet(new_dp);
		call KNoT.dp_complete(new_dp, state->chan_num, state->remote_chan_num, 
		           PACK, NO_PAYLOAD);
		call KNoT.send_on_chan(state,new_dp);
	}

	command void KNoT.close_graceful(ChanState *state){
		DataPayload *new_dp;
		if (state->state != STATE_CONNECTED) {
			PRINTF("Not in Connected state\n");
			return;
		}
		new_dp = &(state->packet);
		clean_packet(new_dp);
		call KNoT.dp_complete(new_dp, state->chan_num, state->remote_chan_num, 
		           DISCONNECT, NO_PAYLOAD);
		call KNoT.send_on_chan(state,new_dp);
		state->state = STATE_DCONNECTED;
	}

	command void KNoT.close_handler(ChanState *state, DataPayload *dp){
		DataPayload *new_dp = &(state->packet);
	  	PRINTF("Sending CLOSE ACK...\n");
		clean_packet(new_dp);
		call KNoT.dp_complete(new_dp, state->chan_num, state->remote_chan_num, 
	               DACK, NO_PAYLOAD);
		call KNoT.send_on_chan(state, new_dp);
	}


/*--------------------------- EVENTS ------------------------------------------------*/
   event void Boot.booted() {
        if (call RadioControl.start() != SUCCESS) {
        	PRINTF("ERROR BOOTING RADIO\n");
        	PRINTFFLUSH();
        }
    }
/*-----------Radio & AM EVENTS------------------------------- */
    event void RadioControl.startDone(error_t error) {
    	PRINTF("*********************\n****** Radio BOOTED *******\n*********************\n");
        PRINTFFLUSH();
    }

    event void RadioControl.stopDone(error_t error) {}

    event void AMSend.sendDone(message_t* msg, error_t error) {
        //if (error == SUCCESS) report_sent();
        //else report_problem();

        sendBusy = FALSE;
    }
}