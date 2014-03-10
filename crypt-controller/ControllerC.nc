#include <string.h>
#include <stdlib.h>
#include "Timer.h"
#include "ChannelTable.h"
#include "ChannelState.h"
#include "KNoTProtocol.h"
#include "KNoT.h"
#include "ECC.h"
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

#define HOME_CHANNEL 0
#define isAsymActive() 1
#define VALID_PKC 1

module ControllerC @safe()
{
  uses {
    interface Boot;
    interface SplitControl as SerialControl;
    interface AMSend as SerialSend;
    interface Receive as SerialReceive;
    interface Timer<TMilli> as CleanerTimer;
    interface LEDBlink;
    interface ChannelTable;
    interface ChannelState;
    interface KNoTCrypt as KNoT;
  }
}
implementation
{
	ChanState home_chan;
	bool serialSendBusy = FALSE;
	uint8_t testKey[] = {0x05,0x15,0x25,0x35,0x45,0x55,0x65,0x75,0x85,0x95};
	uint8_t testKey_size = 10;
  Point publicKey = { .x = {0xe5bc, 0x07c6, 0xd567, 0x0f63, 0x39d9, 0x3287, 0x69c2, 0x9c03, 0x1e0e, 0x49b4},
                      .y = {0x8f83, 0x0e9c, 0x3edc, 0x111c, 0x2a03, 0x6d23, 0x5ed9, 0x6701, 0x08b5, 0x26e0}
                    };
  Point pkc_signature = { .x = {0xe8ae, 0x6b16, 0xa79d, 0x163b, 0xfccc, 0xb830, 0xd7e4, 0xc5e6, 0x5c10, 0x9fa1},
                          .y = {0x86a6, 0x5032, 0x4672, 0x89a6, 0xf5a9, 0x31e0, 0x919d, 0x7722, 0x5438, 0x7122}
                        };
  uint16_t privateKey[10] = {0xbf3d, 0x27bd, 0x26a3, 0xa2d7, 0x1225, 0x2cc1, 0x7899, 0xd02d, 0x914c, 0x1382};
  /* Checks the timer for a channel's state, retransmitting when necessary */
	void check_timer(ChanState *state) {
    decrement_ticks(state);
    if (ticks_left(state)) return;
    if (attempts_left(state)) {
    	if (in_waiting_state(state)) 
        call KNoT.send_on_chan(state, (PDataPayload *)&(state->packet));
      else 
        call KNoT.ping(state); /* PING A LING LONG */
      set_ticks(state, state->ticks * 2); /* Exponential (double) retransmission */
      decrement_attempts(state);
      PRINTF("CLN>> Attempts left %d\n", state->attempts_left);
      PRINTF("CLN>> Retrying packet...\n");
    } else {
      PRINTF("CLN>> CLOSING CHANNEL DUE TO TIMEOUT\n");
      call KNoT.close_graceful(state);
      call ChannelTable.remove_channel(state->chan_num);
    }
	}

	/* Run once every 20ms */
	void cleaner(){
		ChanState *state;
		int i = 1;
    for (; i < CHANNEL_NUM; i++) {
    	state = call ChannelTable.get_channel_state(i);
      if (state) check_timer(state);
    }
    /*if (home_channel_state.state != STATE_IDLE) {
            check_timer(&home_channel_state);
    }*/
	}


  uint8_t pkc_verification(PDataPayload *pdp, uint8_t src){
    /*Assume most certificates will be good */
    ChanState *state = call ChannelTable.new_channel(); 
    if (call KNoT.asym_pkc_handler(state, pdp) != VALID_PKC) {
      call ChannelTable.remove_channel(state->chan_num);
      return 0;
    }
    state = call ChannelTable.new_channel();
    state->remote_addr = src;
    state->seqno = pdp->dp.hdr.seqno;
    return state->chan_num;
  }
      
	/*------------------------------------------------- */
	
	event void Boot.booted() {
		PRINTF("\n*********************\n****** BOOTED *******\n*********************\n");
    PRINTFFLUSH();
    call LEDBlink.report_problem();
    call ChannelTable.init_table();
    call ChannelState.init_state(&home_chan, 0);
    call CleanerTimer.startPeriodic(TICK_RATE);
    call KNoT.init_symmetric(&home_chan, testKey, testKey_size);
    call KNoT.init_asymmetric(privateKey, &publicKey, &pkc_signature);
    }
    
 	event void SerialControl.startDone(error_t error) {}

  event void SerialControl.stopDone(error_t error) {}
   
/*-----------Received packet event, main state event ------------------------------- */
  event message_t* KNoT.receive(uint8_t src, message_t* msg, void* payload, uint8_t len) {
    uint8_t valid = 0;
  	ChanState *state;
  	uint8_t cmd;
  	Packet *p = (Packet *) payload;
    SSecPacket *sp = NULL;
    PDataPayload *pdp = NULL;
    ChanHeader *ch = NULL;
	/* Gets data from the connection */
	  PRINTF("SEC>> Received %s packet\n", is_symmetric(p->flags)?"Symmetric":
    			                               is_asymmetric(p->flags)?"Asymmetric":"Plain");

  	if (is_symmetric(p->flags)) {
      PRINTF("SEC>> IV: %d\n", sp->flags & (0xff >> 2));PRINTFFLUSH();
  		sp = (SSecPacket *) p;
      if (sp->ch.dst_chan_num) { /* Get CC for channel */ 
        state = call ChannelTable.get_channel_state(sp->ch.dst_chan_num);
        if (!state){ /* If bogus request kill bogie */
          PRINTF("Channel %d doesn't exist\n", ch->dst_chan_num);
          state = &home_chan;
          state->remote_chan_num = ch->src_chan_num;
          state->remote_addr = src;
          state->seqno = pdp->dp.hdr.seqno;
          call KNoT.close_graceful(state);
          return msg;
        }
      }
      else state = &home_chan;

  		call KNoT.receiveDecrypt(state, sp, len, &valid);
      if (!valid) return msg; /* Return if decryption failed */

  		pdp = (PDataPayload *) (&sp->ch); /* Offsetting to start of pdp */
  	} 
    else if (is_asymmetric(p->flags)) {
      if (!isAsymActive()) return msg; /* Don't waste time/energy */
      pdp = (PDataPayload *) &(p->ch);
      if (pdp->dp.hdr.cmd == ASYM_QUERY){
        if (pkc_verification(pdp, src) == FAIL) return msg;
        call KNoT.send_asym_resp(state);
        set_state(state, STATE_ASYM_RESP);
      }
      else if (pdp->dp.hdr.cmd == ASYM_RESPONSE){
        if (pkc_verification(pdp, src) == FAIL) return msg;
        call KNoT.send_resp_ack(state);
        set_state(state, STATE_ASYM_RESP);
      }
      else if (pdp->dp.hdr.cmd == ASYM_RESP_ACK){
        state = call ChannelTable.get_channel_state(ch->dst_chan_num);
        if (!state) return msg;
        call KNoT.asym_request_key(state);
        set_state(state, STATE_ASYM_REQ_KEY);
      }
      else if (pdp->dp.hdr.cmd == ASYM_KEY_REQ){
        state = call ChannelTable.get_channel_state(ch->dst_chan_num);
        if (!state) return msg;
        call KNoT.asym_key_request_handler(state, pdp);
      }
      return msg;
    }
    else pdp = (PDataPayload *) &(p->ch);

    ch = &(pdp->ch);
  	cmd = pdp->dp.hdr.cmd;
  	PRINTF("CON>> Received packet from Thing: %d\n", src);
  	PRINTF("CON>> Received a %s command\n", cmdnames[cmd]);
  	PRINTF("CON>> Message for channel %d\n", ch->dst_chan_num);
  	PRINTFFLUSH();

  	switch(cmd) { /* Drop packets for cmds we don't accept */
      case(QUERY): PRINTF("NOT FOR US\n");PRINTFFLUSH(); return msg;
      case(CONNECT): return msg;
      case(QACK): call KNoT.qack_handler(&home_chan, pdp, src); return msg;
      case(DACK): return msg;
  	}
    /* Grab state for requested channel */
  	state = call ChannelTable.get_channel_state(ch->dst_chan_num);
  	if (!state){ /* Attempt to kill connection if no state held */
  		PRINTF("Channel %d doesn't exist\n", ch->dst_chan_num);
  		state = &home_chan;
  		state->remote_chan_num = ch->src_chan_num;
  		state->remote_addr = src;
  		state->seqno = pdp->dp.hdr.seqno;
  		call KNoT.close_graceful(state);
  		return msg;
  	} else if (!call KNoT.valid_seqno(state, pdp)) {
  		PRINTF("Old packet\n");
  		return msg;
  	}
  	switch(cmd) {
  		case(CACK): call KNoT.controller_cack_handler(state, pdp); break;
  		case(RESPONSE): call KNoT.response_handler(state, pdp); break;
  		case(RSYN): call KNoT.response_handler(state, pdp); call KNoT.send_rack(state); break;
  		// case(CMDACK):   	command_ack_handler(state,pdp);break;
  		case(PING): call KNoT.ping_handler(state, pdp); break;
  		case(PACK): call KNoT.pack_handler(state, pdp); break;
  		case(DISCONNECT): call KNoT.disconnect_handler(state, pdp); 
  	                    call ChannelTable.remove_channel(state->chan_num); break;
  		default: PRINTF("Unknown CMD type\n");
  	}
    call LEDBlink.report_received();
    return msg; /* Return packet to TinyOS */
  }

    
	event message_t *SerialReceive.receive(message_t *msg, void* payload, uint8_t len){
  	PDataPayload *pdp = (PDataPayload *)payload;
  	void * data = &(pdp->dp.data);
  	uint8_t cmd = pdp->dp.hdr.cmd;
  	call LEDBlink.report_received();
		
		PRINTF("SERIAL> Serial command received.\n");
		PRINTF("SERIAL> Packet length: %d\n", pdp->dp.dhdr.tlen);
		//PRINTF("SERIAL> Message for channel %d\n", ch->dst_chan_num);
		PRINTF("SERIAL> Command code: %d\n", pdp->dp.hdr.cmd);
		PRINTFFLUSH();

		switch (cmd) {
			case(QUERY): call KNoT.send_asym_query(&home_chan);break;
      //case(QUERY): call KNoT.query(&home_chan, 1/*((QueryMsg*)dp)->type*/);break;
			case(CONNECT): call KNoT.connect(call ChannelTable.new_channel(), 
													             ((SerialConnect*)data)->addr, 
													             ((SerialConnect*)data)->rate);break;
		}
		call LEDBlink.report_received();
  	return msg;
    }

 	event void SerialSend.sendDone(message_t *msg, error_t error){
  	if (error == SUCCESS) call LEDBlink.report_sent();
    else call LEDBlink.report_problem();
    serialSendBusy = FALSE;
  }

   
  event void CleanerTimer.fired(){
  	cleaner();
  }

}