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
#define DEVICE_NAME "WHOAMI"
#define SENSOR_TYPE 0
#define DATA_RATE 10

module KNoTP @safe() {
	provides interface KNoT;
	uses {
		interface Boot;
        interface AMPacket;
        interface AMSend;
        interface SplitControl as RadioControl;
        interface AMSend as SerialAMSend;
        interface Receive as SerialReceive;
        interface LEDBlink;
	}
}
implementation {
	message_t am_pkt;
	message_t serial_pkt;
	bool serialSendBusy = FALSE;
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

	void send_on_serial(DataPayload *dp){
		DataPayload *pkt = (DataPayload *) (call SerialAMSend.getPayload(&serial_pkt, sizeof(DataPayload)));
		memcpy(pkt, dp, sizeof(DataPayload));
		if (call SerialAMSend.send(0, &serial_pkt, sizeof(DataPayload)) == SUCCESS){
			serialSendBusy = TRUE;
		} else {
			PRINTF("Couldn't send serial pkt\n");
			call LEDBlink.report_problem();
		}
	}

	void dp_complete(DataPayload *dp, uint8_t src, uint8_t dst, 
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


/* Higher level calls */

/***** QUERY CALLS AND HANDLERS ******/
	command void KNoT.query(ChanState* state, uint8_t type){
		DataPayload *new_dp = &(state->packet); 
		QueryMsg *q = (QueryMsg *) new_dp->data;
	    clean_packet(new_dp);
	    dp_complete(new_dp, HOME_CHANNEL, HOME_CHANNEL, 
	             QUERY, sizeof(QueryMsg));
	    q->type = type;
	    strcpy((char*)q->name, DEVICE_NAME);
	    call KNoT.knot_broadcast(state, new_dp);
	    //set_ticks(state, TICKS);
	    set_state(state, STATE_QUERY);
	    // Set timer to exit Query state after 5 secs~
	}

	command void KNoT.query_handler(ChanState *state, DataPayload *dp, uint8_t src){
		DataPayload *new_dp;
		QueryResponseMsg *qr;
		QueryMsg *q = (QueryMsg*)(dp->data);
		if (q->type != SENSOR_TYPE){
			PRINTF("Query doesn't match type\n");
			return;
		}
		PRINTF("Query matches type\n");
		state->remote_addr = src;
		new_dp = &(state->packet);
		qr = (QueryResponseMsg*)&(new_dp->data);
		clean_packet(new_dp);
		strcpy((char*)qr->name, DEVICE_NAME); // copy name
		qr->type = SENSOR_TYPE;
		qr->rate = DATA_RATE;
		dp_complete(new_dp, state->chan_num, dp->hdr.src_chan_num, 
					QACK, sizeof(QueryResponseMsg));
		call KNoT.send_on_chan(state, new_dp);
	}

	command void KNoT.qack_handler(ChanState *state, DataPayload *dp, uint8_t src) {
		SerialQueryResponseMsg *qr;
		if (state->state != STATE_QUERY) {
			PRINTF("Not in Query state\n");
			return;
		}
	    state->remote_addr = src; 
		PRINTF("Query ACK received from Thing: \n");
		PRINTF("%d\n",state->remote_addr);
		qr = (SerialQueryResponseMsg *) &dp->data;
		qr->src = state->remote_addr;
		PRINTF("%d\n", qr->src);
		send_on_serial(dp);
	}
/*******************/
	
	command void KNoT.connect(ChanState *state, uint8_t addr, int rate){
		ConnectMsg *cm;
		DataPayload *new_dp;
		state->remote_addr = addr;
		state->rate = rate;
		new_dp = &(state->packet);
		clean_packet(new_dp);
		dp_complete(new_dp, state->chan_num, HOME_CHANNEL, 
	             CONNECT, sizeof(ConnectMsg));
		cm = (ConnectMsg *)(new_dp->data);
		cm->rate = rate;
	    PRINTF("Sending connect request\n");
	    call KNoT.send_on_chan(state, new_dp);
	    set_ticks(state, TICKS);
	    set_state(state, STATE_CONNECT);
		
	}

	command void KNoT.connect_handler(ChanState *state, DataPayload *dp, uint8_t src){
		ConnectMsg *cm;
		DataPayload *new_dp;
		ConnectACKMsg *ck;
		state->remote_addr = src;
		cm = (ConnectMsg*)dp->data;
		PRINTF("%d wants to connect from channel ", dp->hdr.src_chan_num);
		PRINTF("Replying on channel %d", state->chan_num);
		/* Request src must be saved to message back */
		state->remote_chan_num = dp->hdr.src_chan_num;
		if (cm->rate > DATA_RATE){
			state->rate = cm->rate;
		} else {
			state->rate = DATA_RATE;
		}
		PRINTF("The rate is set to: %d", state->rate);
		new_dp = &(state->packet);
		ck = (ConnectACKMsg *)&(new_dp->data);
		clean_packet(new_dp);
		dp_complete(new_dp, state->chan_num, state->remote_chan_num, 
					CACK, sizeof(ConnectACKMsg));
		ck->accept = 1;
		call KNoT.send_on_chan(state, new_dp);
		state->state = STATE_CONNECT;
		// Set up timer to ensure reliability
		//state->timer = set_timer(TIMEOUT, state->chan_num, &reliable_retry);
	}

	command void KNoT.send_rack(ChanState *state){
		DataPayload *new_dp = &(state->packet);
		clean_packet(new_dp);
		dp_complete(new_dp, state->chan_num, state->remote_chan_num, 
	             RACK, NO_PAYLOAD);
		call KNoT.send_on_chan(state, new_dp);
	}

	command uint8_t KNoT.cack_handler(ChanState *state, DataPayload *dp){
		ConnectACKMsg *ck = (ConnectACKMsg*)(dp->data);
		DataPayload *new_dp;
		SerialConnectACKMsg *sck;
		if (state->state != STATE_CONNECT){
			PRINTF("Not in Connecting state\n");
			return -1;
		}
		if (ck->accept == 0){
			PRINTF("SCREAM! THEY DIDN'T EXCEPT!!");
			return 0;
		}
		PRINTF("%d accepts connection request on channel.", state->remote_addr);
		PRINTF("%d\n", dp->hdr.src_chan_num);
		state->remote_chan_num = dp->hdr.src_chan_num;

		new_dp = &(state->packet);
		clean_packet(new_dp);

		dp_complete(new_dp, state->chan_num, state->remote_chan_num, 
	             CACK, NO_PAYLOAD);
		call KNoT.send_on_chan(state,new_dp);
		set_ticks(state, TICKS);
		set_state(state, STATE_CONNECTED);
		//Set up ping timeouts for liveness if no message received or
		// connected to actuator
		sck = (SerialConnectACKMsg *) ck;
		sck->src = state->remote_addr;
		send_on_serial(dp);
		return 1;
	}

	command void KNoT.response_handler(ChanState *state, DataPayload *dp){
		ResponseMsg *rmsg;
		SerialResponseMsg *srmsg;
		if (state->state != STATE_CONNECTED && state->state != STATE_PING){
			PRINTF("Not connected to device!\n");
			return;
		}
		set_ticks(state, TICKS); /* RESET PING TIMER */
		rmsg = (ResponseMsg *)dp->data;
		PRINTF("Data rvd: %d", rmsg->data);
		srmsg = (SerialResponseMsg *)dp->data;
		srmsg->src = state->remote_addr;
		send_on_serial(dp);
	}

	command void KNoT.ping(ChanState *state){
		DataPayload *new_dp = &(state->packet);
		clean_packet(new_dp);
		dp_complete(new_dp, state->chan_num, state->remote_chan_num, 
		           PING, NO_PAYLOAD);
		call KNoT.send_on_chan(state, new_dp);
		state->state = STATE_PING;
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
		dp_complete(new_dp, state->chan_num, state->remote_chan_num, 
		           PACK, NO_PAYLOAD);
		call KNoT.send_on_chan(state,new_dp);
	}

	command void KNoT.pack_handler(ChanState *state, DataPayload *dp){
		if (state->state != STATE_PING) {
			PRINTF("Not in PING state\n");
			return;
		}
		state->state = STATE_CONNECTED;

	}

	command void KNoT.close_graceful(ChanState *state){
		DataPayload *new_dp;
		if (state->state != STATE_CONNECTED) {
			PRINTF("Not in Connected state\n");
			return;
		}
		new_dp = &(state->packet);
		clean_packet(new_dp);
		dp_complete(new_dp, state->chan_num, state->remote_chan_num, 
		           DISCONNECT, NO_PAYLOAD);
		call KNoT.send_on_chan(state,new_dp);
		state->state = STATE_DCONNECTED;
	}

	command void KNoT.close_handler(ChanState *state, DataPayload *dp){
		DataPayload *new_dp = &(state->packet);
	  	PRINTF("Sending CLOSE ACK...\n");
		clean_packet(new_dp);
		dp_complete(new_dp, state->chan_num, state->remote_chan_num, 
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

    event message_t* SerialReceive.receive(message_t* msg, void* payload, uint8_t len) {
    	return msg;
    }
    event void SerialAMSend.sendDone(message_t* msg, error_t error) {
    //if (error == SUCCESS)
        //report_sent();
   // else
        //report_problem();

    sendBusy = FALSE;
    }
}