#include <stdlib.h>
#include "KNoT.h"
#include "BlockCipher.h"
#include "CAPublicKey.h"
#include "NN.h"

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

#define NO_PUBKEY 0
#define CA_PUBKEY 1
#define MY_PUBKEY 2

#define NONCE_LEN 4
                         /* 4(nonce) + 20(KEY_SIZE) + 1 + 20(HMAC) */ 
#define NONCE_CIPHER_LEN NONCE_LEN + KEYDIGITS * NN_DIGIT_LEN + 1  + HMAC_LEN
#define KEY_NONCE_CIPHER_LEN SYM_KEY_SIZE + NONCE_CIPHER_LEN

typedef struct asym_state {
  Point pubKey;
  uint32_t nonce;
} AsymState;

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
    interface ECIES;
    interface Random;
  }
}
implementation {
	message_t am_pkt;

	bool sendBusy = FALSE;
  /* Symmetric state */
	CipherModeContext cc[CHANNEL_NUM + 1];
  AsymState aa[CHANNEL_NUM + 1];
  /* Asymmetric state */
  ECCState CAState;
  ECCState eccState;
  Point *publicKey;
  Point *signature;
  Point client_sig;
  NN_DIGIT *privateKey;
  uint8_t ecdsa_state = NO_PUBKEY; /* Which pubkey is in ecdsa */

  void copy_pkc(AsymQueryPayload *aqp, Point *pubKey, Point *sig){
    memcpy(aqp->pkc.pubKey.x, pubKey->x, 20);
    memcpy(aqp->pkc.pubKey.y, pubKey->y, 20);
    memcpy(aqp->pkc.sig.r, sig->x, 20);
    memcpy(aqp->pkc.sig.s, sig->y, 20);
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
    PDataPayload *pdp = (PDataPayload*) &(state->packet);
		if (state->seqno >= SEQNO_LIMIT){
			state->seqno = SEQNO_START;
		} else {
			state->seqno++;
		}
		pdp->dp.hdr.seqno = state->seqno;
	}
	
	void send(int dest, PDataPayload *pdp){
		uint8_t len = FLAG_SIZE + sizeof(ChanHeader) + sizeof(PayloadHeader) + sizeof(DataHeader) + pdp->dp.dhdr.tlen;
		Packet *payload = (Packet *) (call AMSend.getPayload(&am_pkt, len));
    payload->flags = 0;
		memcpy(&(payload->ch), pdp, len);
    PRINTF("len: %d:%d\n", len, pdp->dp.dhdr.tlen);PRINTFFLUSH();
		if (call AMSend.send(dest, &am_pkt, len) == SUCCESS) {
			sendBusy = TRUE;
			PRINTF("RADIO>> Sent a %s packet to Thing %d, len: %d\n", 
             cmdnames[payload->dp.hdr.cmd], dest,payload->dp.dhdr.tlen);
		}
		else {
			PRINTF("ID: %d, SEND FAILED\n", TOS_NODE_ID);
			call LEDBlink.report_problem();
		}
		PRINTFFLUSH();
	}

	void send_encrypted(int dest, uint8_t chan, PDataPayload *pdp){
    uint8_t cmd = pdp->dp.hdr.cmd;
    uint8_t payload_len = sizeof(PayloadHeader) + sizeof(DataHeader) + pdp->dp.dhdr.tlen;
    uint8_t pkt_len = FLAG_SIZE + MAC_SIZE + sizeof(ChanHeader) + payload_len; 
		SSecPacket *sp = (SSecPacket *) (call AMSend.getPayload(&am_pkt, pkt_len));
		/* Encrypt DataPayload and place into SSecurePacket's DataPayload with tag/mac*/
		call MiniSec.encrypt(&cc[chan], (uint8_t*) &(pdp->dp), payload_len, 
                         (uint8_t*) &(sp->dp), (uint8_t*) &(sp->sh.tag));
    memcpy(&(sp->ch), &(pdp->ch), sizeof(ChanHeader));
		sp->flags = 0;
		sp->flags |= SYMMETRIC_MASK; /* Set symmetric flag */
		sp->flags |= (cc[chan].iv[7] & (0xff >> 2)); /* OR lower 6 bits of IV */
		PRINTF("SEC>> Flags: %d IV: %d\n", sp->flags, (sp->flags & (0xff >> 2)));
    PRINTF("SEC>> Size of encrypted payload: %d\n", payload_len);
		if (call AMSend.send(dest, &am_pkt, pkt_len) == SUCCESS) {
			sendBusy = TRUE;
			PRINTF("RADIO>> Sent a %s packet to Thing %d\n", 
             cmdnames[cmd], dest);		
		}
		else {
			PRINTF("ID: %d, SEND FAILED\n", TOS_NODE_ID);
			call LEDBlink.report_problem();
		}
		PRINTFFLUSH();
	}

  void send_asym(int dest, PDataPayload *pdp){
  	uint8_t i;
    uint8_t len = FLAG_SIZE + sizeof(ChanHeader) + sizeof(PayloadHeader) + sizeof(DataHeader) + pdp->dp.dhdr.tlen;
    Packet *payload = (Packet *) (call AMSend.getPayload(&am_pkt, len));
    payload->flags = 0;
    payload->flags |= ASYMMETRIC_MASK; /* Set asymmetric flag */
    memcpy(&(payload->ch), pdp, len);
    PRINTF("len: %d:%d\n", len, pdp->dp.dhdr.tlen);PRINTFFLUSH();
    if (call AMSend.send(dest, &am_pkt, len) == SUCCESS) {
      sendBusy = TRUE;
      PRINTF("RADIO>> Sent a %s packet to Thing %d, len: %d\n", cmdnames[payload->dp.hdr.cmd], dest, 
                                                                payload->dp.dhdr.tlen);
    }
    else {
      PRINTF("ID: %d, SEND FAILED\n", TOS_NODE_ID);
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

  void send_on_sym_chan(ChanState *state, PDataPayload *pdp){
    increment_seq_no(state);
    send_encrypted(state->remote_addr, state->chan_num, pdp);
  }

	command void KNoT.knot_broadcast(ChanState *state){
		increment_seq_no(state);
		send_encrypted(AM_BROADCAST_ADDR, state->chan_num, 
                   (PDataPayload *)&(state->packet));
	}



/* Higher level calls */

/***** QUERY CALLS AND HANDLERS ******/
	command void KNoT.query(ChanState* state, uint8_t type){
		PDataPayload *new_dp = (PDataPayload *)&(state->packet); 
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
		//SerialQueryResponseMsg *qr;
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
		pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
	             CONNECT, sizeof(ConnectMsg));
		cm = (ConnectMsg *)(new_pdp->dp.data);
		cm->rate = rate;
    send_on_sym_chan(state, new_pdp);
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
		send_on_sym_chan(state, new_pdp);
		set_ticks(state, TICKS);
		set_attempts(state, ATTEMPTS);
		set_state(state, STATE_CONNECT);
		PRINTF("KNOT>> %d wants to connect from channel %d at rate %d\n", src, state->remote_chan_num, 
                                                                      state->rate);
		PRINTF("KNOT>> Replying on channel %d\n", state->chan_num);
		PRINTFFLUSH();
	}

	command uint8_t KNoT.controller_cack_handler(ChanState *state, PDataPayload *pdp){
		ConnectACKMsg *ck = (ConnectACKMsg*)(pdp->dp.data);
		PDataPayload *new_pdp;
		//SerialConnectACKMsg *sck;
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
		send_on_sym_chan(state, new_pdp);
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
    } 
    else if(state->state == STATE_RSYN){
    	clean_packet(new_pdp);
	    new_pdp->dp.hdr.cmd = RSYN; // Send to ensure controller is still out there
	    state->ticks_till_ping = RSYN_RATE;
	    set_state(state, STATE_RACK_WAIT);
    } 
    else if (state->state == STATE_RACK_WAIT){
    	return; /* Waiting for response, no more sensor sends */
    }
    memcpy(&(rmsg->data), data, len);
    new_pdp->ch.src_chan_num = state->chan_num;
	  new_pdp->ch.dst_chan_num = state->remote_chan_num;
    new_pdp->dp.dhdr.tlen = sizeof(ResponseMsg);
    PRINTF("Sending data\n");
    send_on_sym_chan(state, new_pdp);
	}

	command uint8_t KNoT.response_handler(ChanState *state, PDataPayload *pdp, uint8_t *buf){
		ResponseMsg *rmsg;
		if (state->state != STATE_CONNECTED && state->state != STATE_PING){
			PRINTF("KNOT>> Not connected to device!\n");
			return 0;
		}
		set_ticks(state, ticks_till_ping(state->rate)); /* RESET PING TIMER */
		set_attempts(state, ATTEMPTS);
		rmsg = (ResponseMsg *) &(pdp->dp.data);
		memcpy(buf, &(rmsg->data), 1);
		PRINTF("KNOT>> Data rvd: %d\n", buf[0]);
    return 1;
	}

	command void KNoT.send_rack(ChanState *state){
		PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
		clean_packet(new_pdp);
		pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
	             RACK, NO_PAYLOAD);
		send_on_sym_chan(state, new_pdp);
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
		send_on_sym_chan(state, new_pdp);
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
		send_on_sym_chan(state, new_pdp);
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


/*** SYMMETRIC CALLS AND HANDLERS ***/

	command void KNoT.init_symmetric(ChanState *state, uint8_t *key, uint8_t key_size){
    call MiniSec.init(&cc[state->chan_num], key, key_size, 7);
	}

  command void KNoT.receiveDecrypt(ChanState *state, SSecPacket *sp, uint8_t len, uint8_t *valid){
    uint8_t cipher_len = len - sizeof(ChanHeader) - MAC_SIZE - FLAG_SIZE;
    PRINTF("SYM>> e_payload size: %d\n", cipher_len);
    call MiniSec.decrypt(&cc[state->chan_num], sp->flags, (uint8_t *)&(sp->dp), 
                         cipher_len, (uint8_t *)&(sp->dp), (uint8_t *)&(sp->sh.tag), valid);
    PRINTF("SYM>> Valid MAC: %s\n", (*valid?"yes":"no"));PRINTFFLUSH();
  }

  command void KNoT.sym_handover(ChanState *state){
    PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
    clean_packet(new_pdp);
    pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
               SYM_HANDOVER, NO_PAYLOAD);
    send_on_sym_chan(state, new_pdp);
    set_state(state, STATE_IDLE);
  }

  command void KNoT.sym_handover_handler(ChanState *state, PDataPayload *pdp){
    set_state(state, STATE_IDLE);
  }

/*** ASYMMETRIC CALLS AND HANDLERS ***/
	command void KNoT.init_asymmetric(uint16_t *priv_key, Point *pub_key, Point *pkc_sig){
    PRINTF("ECC>> Initialising...");PRINTFFLUSH();
    publicKey = pub_key;
    privateKey = priv_key;
    signature = pkc_sig;
    call ECC.init();
    call ECC.saveState(&eccState);
    call ECDSA.init(&CAPublicKey);
    call ECDSA.saveState(&CAState);
    ecdsa_state = CA_PUBKEY;
    PRINTF("done!\n");PRINTFFLUSH();
  }

  command void KNoT.send_asym_query(ChanState *state){
    /* Send a packet containing signed query + PKC */
    PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
    AsymQueryPayload *a = (AsymQueryPayload *) &(new_pdp->dp.data);
    clean_packet(new_pdp);
    copy_pkc(a, publicKey, signature);
    pdp_complete(new_pdp, HOME_CHANNEL, HOME_CHANNEL, 
                 ASYM_QUERY, sizeof(AsymQueryPayload));
    send_asym(AM_BROADCAST_ADDR, new_pdp);
  }

  command uint8_t KNoT.asym_pkc_handler(ChanState *state, PDataPayload *pdp){
    /* Verify PKC using CA PubKey */
    uint32_t start_t, end_t;
    uint8_t pass = 0, i = 0;
    AsymQueryPayload *a = (AsymQueryPayload *) &(pdp->dp.data);
    uint8_t *msg = (uint8_t *) &(aa[state->chan_num].pubKey);
    memcpy(aa[state->chan_num].pubKey.x, a->pkc.pubKey.x, 20);
    memcpy(aa[state->chan_num].pubKey.y, a->pkc.pubKey.y, 20);
    memcpy(client_sig.x, a->pkc.sig.r, 20);
    memcpy(client_sig.y, a->pkc.sig.s, 20);
    call ECDSA.reinit(&CAState);
    pass = call ECDSA.verify(msg, sizeof(Point), (NN_DIGIT *) (client_sig.x), 
                             (NN_DIGIT *) (client_sig.y), &CAPublicKey);
  	PRINTF("ECC>> Cert verification - %s(%d)\n", (pass == 1 ? "PASSED":"FAILED"), pass);
    return pass;
  }

  command void KNoT.send_asym_resp(ChanState *state){
    /* Send a packet containing signed query + PKC */
    PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
    AsymQueryPayload *a = (AsymQueryPayload *) &(new_pdp->dp.data);
    clean_packet(new_pdp);
    copy_pkc(a, publicKey, signature);
    pdp_complete(new_pdp, state->chan_num, HOME_CHANNEL, 
                 ASYM_RESPONSE, sizeof(AsymQueryPayload));
    send_asym(state->remote_addr, new_pdp);
  }

  command void KNoT.send_resp_ack(ChanState *state){
    PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
    AsymQueryPayload *a = (AsymQueryPayload *) &(new_pdp->dp.data);
    clean_packet(new_pdp);
    pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
                 ASYM_RESP_ACK, sizeof(AsymRespACKPayload));
    send_asym(state->remote_addr, new_pdp);
  }

  command uint32_t KNoT.asym_request_key(ChanState *state){
    NN_DIGIT r[NUMWORDS];
    NN_DIGIT s[NUMWORDS];
    int clen, pass;
    uint32_t nonce = 0;
    PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
    AsymKeyRequestPayload *a = (AsymKeyRequestPayload *) &(new_pdp->dp.data);
    call ECC.reinit(&eccState);
    clean_packet(new_pdp);
    while (nonce == 0) {nonce = call Random.rand32();}
    PRINTF("ECC>> Encrypting Nonce %lu...", nonce); PRINTFFLUSH();
    clen = call ECIES.encrypt((uint8_t *)a->e_nonce, NONCE_CIPHER_LEN, 
                              (uint8_t *) &nonce, NONCE_LEN, 
                               &(aa[state->chan_num].pubKey));
    PRINTF("Done (%dbytes).\nECC>> Signing Nonce...", clen); PRINTFFLUSH();
    call ECDSA.init(publicKey);
    call ECDSA.sign((uint8_t *) a->e_nonce, NONCE_CIPHER_LEN, r, s, privateKey);
    memcpy(a->sig.r, r, NUMWORDS * NN_DIGIT_LEN);
    memcpy(a->sig.s, s, NUMWORDS * NN_DIGIT_LEN);
    PRINTF("done\n");PRINTFFLUSH();
    pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
                 ASYM_KEY_REQ, sizeof(AsymKeyRequestPayload));
    send_asym(state->remote_addr, new_pdp);
     /* 5. Send signed + encrypted response with PKC */ 
		return nonce; 
  }

  command uint32_t KNoT.asym_key_request_handler(ChanState *state, PDataPayload *pdp){
    /* Receive a packet containing signed + encrypted response + PKC */
    uint32_t start_t, end_t;
    uint32_t nonce;
    uint8_t mlen = 0, pass = 0;
    AsymKeyRequestPayload *a = (AsymKeyRequestPayload *) &(pdp->dp.data);
    call ECDSA.init(&(aa[state->chan_num].pubKey));
    pass = call ECDSA.verify((uint8_t *) a->e_nonce, NONCE_CIPHER_LEN, 
                             (uint16_t *) a->sig.r, (uint16_t *) a->sig.s,
                             &(aa[state->chan_num].pubKey));
    PRINTF("ECC>> Signature verification - %s(%d)\n", (pass == 1 ? "PASSED":"FAILED"), pass);
    PRINTFFLUSH();
    if (pass != 1) return 0;
    call ECC.init();
    mlen = call ECIES.decrypt((uint8_t *) &nonce, NONCE_LEN, 
                              (uint8_t *) a->e_nonce, NONCE_CIPHER_LEN, 
                              privateKey);
    PRINTF("ECC>> Decryption - %s(%d)\n", (mlen > 0 ? "SUCCEEDED":"FAILED"), mlen);
    PRINTF("Nonce: %lu\n", nonce);PRINTFFLUSH();
    return nonce;
  }

  command void KNoT.asym_key_resp(ChanState *state, uint32_t nonce, uint8_t *symKey){
    NN_DIGIT r[NUMWORDS];
    NN_DIGIT s[NUMWORDS];
  	uint8_t clen = 0, pass = 0, i = 0;
  	PDataPayload *new_pdp = (PDataPayload *) &(state->packet);
    AsymKeyRespPayload *a = (AsymKeyRespPayload *) &(new_pdp->dp.data);
    AsymKeyPayload k = {.nonce = nonce};
    memcpy(&(k.sKey), symKey, SYM_KEY_SIZE);
    call ECC.reinit(&eccState);
    clean_packet(new_pdp);
    PRINTF("ECC>> Encrypting key + nonce..."); PRINTFFLUSH();
    clen = call ECIES.encrypt((uint8_t *) a->e_payload, KEY_NONCE_CIPHER_LEN, 
                              (uint8_t *) &k, SYM_KEY_SIZE + NONCE_LEN, 
                               &(aa[state->chan_num].pubKey));
    PRINTF("Done (%dbytes).\nECC>> Signing key + nonce...", clen); PRINTFFLUSH();
    call ECDSA.init(publicKey);
    call ECDSA.sign((uint8_t *) a->e_payload, KEY_NONCE_CIPHER_LEN, r, s, privateKey);
    memcpy(a->sig.r, r, NUMWORDS * NN_DIGIT_LEN);
    memcpy(a->sig.s, s, NUMWORDS * NN_DIGIT_LEN);
    PRINTF("done\n");PRINTFFLUSH();
    pdp_complete(new_pdp, state->chan_num, state->remote_chan_num, 
                 ASYM_KEY_RESP, sizeof(AsymKeyRespPayload));
    send_asym(state->remote_addr, new_pdp);
    memcpy(state->key, symKey, SYM_KEY_SIZE);
  }

  command uint8_t KNoT.asym_key_resp_handler(ChanState *state, PDataPayload *pdp, uint32_t nonce){
		uint32_t start_t, end_t;
    int8_t mlen = 0;
    uint8_t pass = 0, i = 0;
    AsymKeyPayload k;
    AsymKeyRespPayload *a = (AsymKeyRespPayload *) &(pdp->dp.data);
    call ECDSA.init(&(aa[state->chan_num].pubKey));
    pass = call ECDSA.verify((uint8_t *) a->e_payload, KEY_NONCE_CIPHER_LEN, 
                             (uint16_t *) a->sig.r, (uint16_t *) a->sig.s,
                             &(aa[state->chan_num].pubKey));
    PRINTF("ECC>> Signature verification - %s(%d)\n", (pass == 1 ? "PASSED":"FAILED"), pass);
    PRINTFFLUSH();
    if (pass != 1) return 0;
    call ECC.init();
    mlen = call ECIES.decrypt((uint8_t *) &k, SYM_KEY_SIZE + NONCE_LEN, 
                              (uint8_t *) a->e_payload, KEY_NONCE_CIPHER_LEN, 
                              privateKey);
    PRINTF("ECC>> Decryption - %s(%d)\n", (mlen > 0 ? "SUCCEEDED":"FAILED"), mlen);
    PRINTF("Nonce: %lu\n", k.nonce);
    PRINTFFLUSH();
    if (nonce != k.nonce) return 0;
    PRINTF("ECC>> KEY EXCHANGE SUCCEEDED\n");
    PRINTFFLUSH();
    memcpy(state->key, k.sKey, SYM_KEY_SIZE);
    return 1;
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
    	PRINTF("*** RADIO BOOTED ****\n");
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