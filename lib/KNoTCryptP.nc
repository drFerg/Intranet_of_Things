#include <stdlib.h>
#include "KNoT.h"
#include "BlockCipher.h"
#include "CAPublicKey.h"

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
#ifndef DEVICE_NAME
#define DEVICE_NAME "WHOAMI"
#endif
#ifndef SENSOR_TYPE
#define SENSOR_TYPE 0
#endif
#ifndef DATA_RATE
#define DATA_RATE 10
#endif

#define FLAG_SIZE 1
#define MSG_LEN 3

module KNoTCryptP @safe() {
	provides interface KNoTCrypt as KNoT;
	uses {
		interface Boot;
    interface AMPacket;
    interface Receive;
    interface AMSend;
    interface SplitControl as RadioControl;
    interface LEDBlink;
    interface MiniSec;
    interface NN;
    interface ECC;
    interface ECDSA;
  }
}
implementation {
	message_t am_pkt;
	message_t serial_pkt;
	bool serialSendBusy = FALSE;
	bool sendBusy = FALSE;
	CipherModeContext cc[CHANNEL_NUM + 1];
  /* Symmetric state */
  Point PublicKey;
  NN_DIGIT PrivateKey[NUMWORDS];
  uint8_t message[MSG_LEN];
  NN_DIGIT r[NUMWORDS];
  NN_DIGIT s[NUMWORDS];
  uint32_t t;
  uint8_t pass;

  void dp_complete(DataPayload *dp, uint8_t src, uint8_t dst, 
               uint8_t cmd, uint8_t len){
    //dp->hdr.src_chan_num = src; 
    //dp->hdr.dst_chan_num = dst; 
    dp->hdr.cmd = cmd; 
    dp->dhdr.tlen = len;
  }
  void pdp_complete(PDataPayload *pdp, uint8_t src, uint8_t dst, 
               uint8_t cmd, uint8_t len){
    pdp->ch.src_chan_num = src; 
    pdp->ch.dst_chan_num = dst; 
    pdp->dp.hdr.cmd = cmd; 
    pdp->dp.dhdr.tlen = len;
  }
  void sp_complete(SSecPacket *sp, uint8_t src, uint8_t dst, 
               uint8_t cmd, uint8_t len){
    sp->ch.src_chan_num = src; 
    sp->ch.dst_chan_num = dst; 
    sp->dp.hdr.cmd = cmd; 
    sp->dp.dhdr.tlen = len;
  }

	void increment_seq_no(ChanState *state){
		if (state->seqno >= SEQNO_LIMIT){
			state->seqno = SEQNO_START;
		} else {
			state->seqno++;
		}
		((PDataPayload*) &(state->packet))->dp.hdr.seqno = state->seqno;
	}
	
	void send(int dest, PDataPayload *pdp){
		uint8_t len = FLAG_SIZE + sizeof(ChanHeader) + sizeof(PayloadHeader) + sizeof(DataHeader) + pdp->dp.dhdr.tlen;
		Packet *payload = (Packet *) (call AMSend.getPayload(&am_pkt, len));
    payload->flags = 0;
		memcpy(&(payload->ch), pdp, len);
		if (call AMSend.send(dest, &am_pkt, len) == SUCCESS) {
			sendBusy = TRUE;
			PRINTF("RADIO>> Sent a %s packet to Thing %d\n", cmdnames[payload->dp.hdr.cmd], dest);		
			PRINTF("RADIO>> KNoT Payload Length: %d\n", payload->dp.dhdr.tlen);
		}
		else {
			PRINTF("ID: %d, Radio Msg could not be sent, channel busy\n", TOS_NODE_ID);
			call LEDBlink.report_problem();
		}
		PRINTFFLUSH();
	}

	void send_encrypted(int dest, uint8_t chan, PDataPayload *pdp){
    int i;
    uint8_t payload_len = sizeof(PayloadHeader) + sizeof(DataHeader) + pdp->dp.dhdr.tlen;
    uint8_t pkt_len = FLAG_SIZE + MAC_SIZE + sizeof(ChanHeader) + payload_len; 
		SSecPacket *sp = (SSecPacket *) (call AMSend.getPayload(&am_pkt, pkt_len));
		/* Encrypt DataPayload and place into SSecurePacket's DataPayload with tag/mac*/
		call MiniSec.encrypt(&cc[chan], (uint8_t*) &(pdp->dp), payload_len, 
                         (uint8_t*) &(sp->dp), (uint8_t*) &(sp->sh.tag));
    memcpy(&(sp->ch), &(pdp->ch), sizeof(ChanHeader));
    PRINTF("len_to_send: %d\n", pkt_len);
		sp->flags = 0;
		sp->flags |= SYMMETRIC_MASK; /* Set symmetric flag */
		sp->flags |= (cc[chan].iv[7] & (0xff >> 2)); /* OR lower 6 bits of IV */
		PRINTF("SEC>> Flags: %d\n", sp->flags);
		PRINTF("SEC>> IV: %d\n", (sp->flags & (0xff >> 2)));
    PRINTF("SEC>> Size of encrypted payload: %d\n", payload_len);
		//memcpy(payload, sp, len);
		if (call AMSend.send(dest, &am_pkt, pkt_len) == SUCCESS) {
			sendBusy = TRUE;
			PRINTF("RADIO>> Sent a packet to Thing %d\n", dest);		
			//PRINTF("RADIO>> KNoT Payload Length: %d\n", len);
		}
		else {
			PRINTF("ID: %d, Radio Msg could not be sent, channel busy\n", TOS_NODE_ID);
			call LEDBlink.report_problem();
		}
		PRINTFFLUSH();
	}



	command int KNoT.valid_seqno(ChanState *state, PDataPayload *pdp){
		if (state->seqno > pdp->dp.hdr.seqno){ // Old packet or sender confused
			return 0;
		} else {
			state->seqno = pdp->dp.hdr.seqno;
			if (state->seqno >= SEQNO_LIMIT){
				state->seqno = SEQNO_START;
			}
			return 1;
		}
	}

	command void KNoT.send_on_chan(ChanState *state, PDataPayload *pdp){
		increment_seq_no(state);
		send(state->remote_addr, pdp);
	}

	command void KNoT.knot_broadcast(ChanState *state){
		increment_seq_no(state);
		send_encrypted(AM_BROADCAST_ADDR, state->chan_num, &(state->packet));
	}

  command void KNoT.receiveDecrypt(ChanState *state, SSecPacket *sp, uint8_t len, uint8_t *valid){
    uint8_t cipher_len = len - sizeof(ChanHeader) - MAC_SIZE - FLAG_SIZE;
    PRINTF("Size of encrypted payload: %d\n", cipher_len);
    call MiniSec.decrypt(&cc[state->chan_num], sp->flags, (uint8_t *)&(sp->dp), 
                         cipher_len, (uint8_t *)&(sp->dp), (uint8_t *)&(sp->sh.tag), valid);
    PRINTF("Valid MAC: %s\n", (*valid?"yes":"no"));PRINTFFLUSH();
  }

/* Higher level calls */

/***** QUERY CALLS AND HANDLERS ******/
	command void KNoT.query(ChanState* state, uint8_t type){
		PDataPayload *new_dp = &(state->packet); 
		QueryMsg *q;
    clean_packet(new_dp);
    pdp_complete(new_dp, HOME_CHANNEL, HOME_CHANNEL, 
             QUERY, sizeof(QueryMsg));
    q = (QueryMsg *) &(new_dp->dp.data);
    q->type = type;
    strcpy((char*)q->name, DEVICE_NAME);
    call KNoT.knot_broadcast(state);
    set_ticks(state, TICKS);
    set_state(state, STATE_QUERY);
    // Set timer to exit Query state after 5 secs~
	}

	command void KNoT.query_handler(ChanState *state, PDataPayload *pdp, uint8_t src){
		PDataPayload *new_pdp;
		QueryResponseMsg *qr;
		QueryMsg *q = (QueryMsg*) &(pdp->dp.data);
		if (q->type != SENSOR_TYPE) {
			PRINTF("Query doesn't match type\n");
			return;
		}
		PRINTF("Query matches type\n");
		state->remote_addr = src;
		new_pdp = (PDataPayload *) &(state->packet);
		qr = (QueryResponseMsg*) &(new_pdp->dp.data);
		clean_packet(new_pdp);
		strcpy((char*)qr->name, DEVICE_NAME); /* copy name */
		qr->type = SENSOR_TYPE;
		qr->rate = DATA_RATE;
		pdp_complete(new_pdp, state->chan_num, pdp->ch.src_chan_num, 
					QACK, sizeof(QueryResponseMsg));
		call KNoT.send_on_chan(state, new_pdp);
	}

	command void KNoT.qack_handler(ChanState *state, PDataPayload *pdp, uint8_t src) {
		SerialQueryResponseMsg *qr;
		if (state->state != STATE_QUERY) {
			PRINTF("KNOT>> Not in Query state\n");
			return;
		}
	    state->remote_addr = src; 
		//qr = (SerialQueryResponseMsg *) &dp->data;
		//qr->src = state->remote_addr;
		//send_on_serial(dp);
	}

/*********** CONNECT CALLS AND HANDLERS ********/
	
	command void KNoT.connect(ChanState *state, uint8_t addr, int rate){
		ConnectMsg *cm;
		PDataPayload *new_pdp;
		state->remote_addr = addr;
		state->rate = rate;
		new_pdp = (PDataPayload *) &(state->packet);
		clean_packet(new_pdp);
		pdp_complete(new_pdp, state->chan_num, HOME_CHANNEL, 
	             CONNECT, sizeof(ConnectMsg));
		cm = (ConnectMsg *)(new_pdp->dp.data);
		cm->rate = rate;
    call KNoT.send_on_chan(state, new_pdp);
    set_ticks(state, TICKS);
    set_attempts(state, ATTEMPTS);
    set_state(state, STATE_CONNECT);
   	PRINTF("KNOT>> Sent connect request from chan %d\n", state->chan_num);
    PRINTFFLUSH();
	}

	command void KNoT.connect_handler(ChanState *state, PDataPayload *pdp, uint8_t src){
		ConnectMsg *cm;
		PDataPayload *new_pdp;
		ConnectACKMsg *ck;
		state->remote_addr = src;
		cm = (ConnectMsg*) &(pdp->dp.data);
		/* Request src must be saved to message back */
		state->remote_chan_num = pdp->ch.src_chan_num;
		if (cm->rate > DATA_RATE) state->rate = cm->rate;
		else state->rate = DATA_RATE;
		new_pdp = (PDataPayload *) &(state->packet);
		ck = (ConnectACKMsg *)&(new_pdp->dp.data);
		clean_packet(new_pdp);
		pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
					CACK, sizeof(ConnectACKMsg));
		ck->accept = 1;
		call KNoT.send_on_chan(state, new_pdp);
		set_ticks(state, TICKS);
		set_attempts(state, ATTEMPTS);
		set_state(state, STATE_CONNECT);
		PRINTF("KNOT>> %d wants to connect from channel %d\n", src, state->remote_chan_num);
		PRINTFFLUSH();
		PRINTF("KNOT>> Replying on channel %d\n", state->chan_num);
		PRINTF("KNOT>> The rate is set to: %d\n", state->rate);
		PRINTFFLUSH();
	}

	command uint8_t KNoT.controller_cack_handler(ChanState *state, PDataPayload *pdp){
		ConnectACKMsg *ck = (ConnectACKMsg*)(pdp->dp.data);
		PDataPayload *new_pdp;
		SerialConnectACKMsg *sck;
		if (state->state != STATE_CONNECT){
			PRINTF("KNOT>> Not in Connecting state\n");
			return -1;
		}
		if (ck->accept == 0){
			PRINTF("KNOT>> SCREAM! THEY DIDN'T EXCEPT!!\n");
			return 0;
		}
		PRINTF("KNOT>> %d accepts connection request on channel %d\n", 
        		state->remote_addr,
        		pdp->ch.src_chan_num);
    PRINTFFLUSH();
		state->remote_chan_num = pdp->ch.src_chan_num;
		new_pdp = (PDataPayload *) &(state->packet);
		clean_packet(new_pdp);
		pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
	             CACK, NO_PAYLOAD);
		call KNoT.send_on_chan(state, new_pdp);
		set_ticks(state, ticks_till_ping(state->rate));
		set_attempts(state, ATTEMPTS);
		set_state(state, STATE_CONNECTED);
		//Set up ping timeouts for liveness if no message received or
		// connected to actuator
		//sck = (SerialConnectACKMsg *) ck;
		//sck->src = state->remote_addr;
		//send_on_serial(dp);
		return 1;
	}

	command uint8_t KNoT.sensor_cack_handler(ChanState *state, PDataPayload *pdp){
		if (state->state != STATE_CONNECT){
			PRINTF("KNOT>> Not in Connecting state\n");
			return 0;
		}
		set_ticks(state, ticks_till_ping(state->rate));
		PRINTF("KNOT>> TX rate: %d\n", state->rate);
		PRINTF("KNOT>> CONNECTION FULLY ESTABLISHED<<\n");PRINTFFLUSH();
		set_state(state, STATE_CONNECTED);
		return 1;
	}

/**** RESPONSE CALLS AND HANDLERS ***/
	command void KNoT.send_value(ChanState *state, uint8_t *data, uint8_t len){
    PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
		ResponseMsg *rmsg = (ResponseMsg*)&(new_pdp->dp.data);
		// Send a Response SYN or Response
		if (state->state == STATE_CONNECTED){
      clean_packet(new_pdp);
      new_pdp->dp.hdr.cmd = RESPONSE;
      state->ticks_till_ping--;
    } else if(state->state == STATE_RSYN){
    	clean_packet(new_pdp);
	    new_pdp->dp.hdr.cmd = RSYN; // Send to ensure controller is still out there
	    state->ticks_till_ping = RSYN_RATE;
	    set_state(state, STATE_RACK_WAIT);
    } else if (state->state == STATE_RACK_WAIT){
    	return; /* Waiting for response, no more sensor sends */
    }
    memcpy(&(rmsg->data), data, len);
    new_pdp->ch.src_chan_num = state->chan_num;
	  new_pdp->ch.dst_chan_num = state->remote_chan_num;
    new_pdp->dp.dhdr.tlen = sizeof(ResponseMsg);
    PRINTF("Sending data\n");
    call KNoT.send_on_chan(state, new_pdp);
	}

	command void KNoT.response_handler(ChanState *state, PDataPayload *pdp){
		ResponseMsg *rmsg;
		SerialResponseMsg *srmsg;
		uint8_t temp;
		if (state->state != STATE_CONNECTED && state->state != STATE_PING){
			PRINTF("KNOT>> Not connected to device!\n");
			return;
		}
		set_ticks(state, ticks_till_ping(state->rate)); /* RESET PING TIMER */
		set_attempts(state, ATTEMPTS);
		rmsg = (ResponseMsg *) &(pdp->dp.data);
		memcpy(&temp, &(rmsg->data), 1);
		PRINTF("KNOT>> Data rvd: %d\n", temp);
		PRINTF("Temp: %d\n", temp);
		//srmsg = (SerialResponseMsg *)dp->data;
		//srmsg->src = state->remote_addr;
		//send_on_serial(dp);
	}

	command void KNoT.send_rack(ChanState *state){
		PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
		clean_packet(new_pdp);
		pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
	             RACK, NO_PAYLOAD);
		call KNoT.send_on_chan(state, new_pdp);
	}
	command void KNoT.rack_handler(ChanState *state, PDataPayload *pdp){
		if (state->state != STATE_RACK_WAIT){
			PRINTF("KNOT>> Didn't ask for a RACK!\n");
			return;
		}
		set_state(state, STATE_CONNECTED);
		set_ticks(state, ticks_till_ping(state->rate));
		set_attempts(state, ATTEMPTS);
	}

/*** PING CALLS AND HANDLERS ***/
	command void KNoT.ping(ChanState *state){
		PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
		clean_packet(new_pdp);
		pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
		           PING, NO_PAYLOAD);
		call KNoT.send_on_chan(state, new_pdp);
		set_state(state, STATE_PING);
	}

	command void KNoT.ping_handler(ChanState *state, PDataPayload *pdp){
		PDataPayload *new_pdp;
		if (state->state != STATE_CONNECTED) {
			PRINTF("KNOT>> Not in Connected state\n");
			return;
		}
		new_pdp = (PDataPayload *) &(state->packet);
		clean_packet(new_pdp);
		pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
		           PACK, NO_PAYLOAD);
		call KNoT.send_on_chan(state, new_pdp);
	}

	command void KNoT.pack_handler(ChanState *state, PDataPayload *pdp){
		if (state->state != STATE_PING) {
			PRINTF("KNOT>> Not in PING state\n");
			return;
		}
		set_state(state, STATE_CONNECTED);
		set_ticks(state, ticks_till_ping(state->rate));
		set_attempts(state, ATTEMPTS);
	}

/*** DISCONNECT CALLS AND HANDLERS ***/
	command void KNoT.close_graceful(ChanState *state){
		PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
		clean_packet(new_pdp);
		pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
		           DISCONNECT, NO_PAYLOAD);
		call KNoT.send_on_chan(state, new_pdp);
		set_state(state, STATE_DCONNECTED);
	}
	command void KNoT.disconnect_handler(ChanState *state, PDataPayload *pdp){
		PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
		clean_packet(new_pdp);
		pdp_complete(new_pdp, pdp->ch.src_chan_num, state->remote_chan_num, 
	               DACK, NO_PAYLOAD);
		call KNoT.send_on_chan(state, new_pdp);
	}

	command void KNoT.init_symmetric(ChanState *state, uint8_t *key, uint8_t key_size){
		call MiniSec.init(&cc[state->chan_num], key, key_size, 7);

	}
	command void KNoT.init_assymetric(uint16_t *priv_key, uint16_t *pub_key_x,
                                    uint16_t *pub_key_y, uint8_t key_size){
	    //init message
	    memset(message, 0, MSG_LEN);
	    //init private key
	    memset(PrivateKey, 0, NUMWORDS*NN_DIGIT_LEN);
	    //init public key
	    memset(PublicKey.x, 0, NUMWORDS*NN_DIGIT_LEN);
	    memset(PublicKey.y, 0, NUMWORDS*NN_DIGIT_LEN);
	    //init signature
	    memset(r, 0, NUMWORDS*NN_DIGIT_LEN);
	    memset(s, 0, NUMWORDS*NN_DIGIT_LEN);
      memcpy(PrivateKey, priv_key, key_size*NN_DIGIT_LEN);
      memcpy(PublicKey.x, pub_key_x, key_size*NN_DIGIT_LEN);
      memcpy(PublicKey.y, pub_key_y, key_size*NN_DIGIT_LEN);
      call ECC.init();
	}

/*--------------------------- EVENTS ------------------------------------------------*/
   event void Boot.booted() {
        if (call RadioControl.start() != SUCCESS) {
        	PRINTF("RADIO>> ERROR BOOTING RADIO\n");
        	PRINTFFLUSH();
        }
    }

/*-----------Radio & AM EVENTS------------------------------- */
    event void RadioControl.startDone(error_t error) {
    	PRINTF("*********************\n*** RADIO BOOTED ****\n*********************\n");
    	PRINTF("RADIO>> ADDR: %d\n", call AMPacket.address());
        PRINTFFLUSH();
    }

    event void RadioControl.stopDone(error_t error) {}
	
	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
		return signal KNoT.receive(call AMPacket.source(msg), msg, payload, len);
	}

    event void AMSend.sendDone(message_t* msg, error_t error) {
        if (error == SUCCESS) {
        	call LEDBlink.report_sent();
        	PRINTF("RADIO>> Packet sent successfully\n");
        } else call LEDBlink.report_problem();
        sendBusy = FALSE;
    }



}