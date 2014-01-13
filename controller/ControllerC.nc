#include <string.h>
#include <stdlib.h>
#include "Timer.h"
#include "ChannelTable.h"
#include "ChannelState.h"
#include "KNoTProtocol.h"
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

module ControllerC @safe()
{
    uses {
        interface Boot;
        interface AMPacket;
        interface SplitControl as RadioControl;
        interface AMSend as RadioAMSend;
        //interface AMSend as SerialAMSend;
        interface Receive as RadioReceive;
        //interface Receive as SerialReceive;
        interface Timer<TMilli>;
        interface Timer<TMilli> as LEDTimer0;
        interface Timer<TMilli> as LEDTimer1;
        interface Timer<TMilli> as LEDTimer2;
        interface Read<uint16_t> as LightSensor;
        interface Read<uint16_t> as TempSensor;
        interface Leds;
        interface ChannelTable;
        interface ChannelState;
    }
}
implementation
{
	typedef struct channel_state{
   uint8_t remote_addr; //Holds address of remote device
   uint8_t state;
   uint8_t seqno;
   uint8_t chan_num;
   uint8_t remote_chan_num;
   uint8_t ticks;
   uint8_t ticks_left;
   uint16_t rate;
   uint8_t ticks_till_ping;
   uint8_t attempts_left;
   uint8_t timer;
   DataPayload packet;
}ChannelState;
	message_t am_pkt;
	char controller_name[] = "The Boss";
	SerialQueryResponseMsg qr;
	ChannelState a;
	int serial_ready = 0;
	char buf[50];
	int serial_index = 0;
	int addr = 0;
	char serialpkt[32];

	/*-----------LED Commands------------------------------- */
    void pulse_green_led(int t){
        call Leds.led1Toggle();
        call LEDTimer2.startOneShot(t);
    }

    void pulse_red_led(int t){
        call Leds.led0Toggle();
        call LEDTimer0.startOneShot(t);
    }

    void pulse_blue_led(int t){
        call Leds.led2Toggle();
        call LEDTimer1.startOneShot(t);
    }
	/*------------------------------------------------------- */

	/*-----------Reports------------------------------- */
  	// Use LEDs to report various status issues.
    void report_problem() { PRINTF("ID: %d, Problem\n",TOS_NODE_ID);pulse_red_led(1000);pulse_blue_led(1000);pulse_green_led(1000); }
    void report_sent() {PRINTF("ID: %d, Sent tweet\n",TOS_NODE_ID);pulse_green_led(100);}
    void report_received() {PRINTF("ID: %d, Received tweet\n",TOS_NODE_ID);PRINTFFLUSH();pulse_red_led(100);pulse_blue_led(100);}
    void report_dropped(){PRINTF("ID: %d, Dropped tweet\n----------\n",TOS_NODE_ID);PRINTFFLUSH();pulse_red_led(1000);}
      
	/*------------------------------------------------- */

	void dp_complete(DataPayload *dp, uint8_t src, uint8_t dst, 
             uint8_t cmd, uint8_t len){
	   dp->hdr.src_chan_num = src; 
	   dp->hdr.dst_chan_num = dst; 
	   dp->hdr.cmd = cmd; 
	   dp->dhdr.tlen = len;
	}

	void increment_seq_no(ChannelState *state, DataPayload *dp){
	   if (state->seqno >= SEQNO_LIMIT){
	      state->seqno = SEQNO_START;
	   } else {
	      state->seqno++;
	   }
	   dp->hdr.seqno = state->seqno;
	}

	int valid_seqno(ChannelState *state, DataPayload *dp){
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

	void qack_handler(DataPayload *dp, uint8_t src) {
	    ChannelState *state = &home_channel_state;
		if (state->state != STATE_QUERY) {
			PRINTF("Not in Query state\n");
			return;
		}
	    state->remote_addr = src; 
		PRINTF("Query ACK received from Thing: \n");
		PRINTF("%d\n",state->remote_addr);
		SerialQueryResponseMsg *qr = (SerialQueryResponseMsg *) &dp->data;
		qr->src = state->remote_addr;
		PRINTF("%d\n", qr->src);
		/*if (call SerialAMRadio.send((char *)dp, sizeof(DataPayload)) == SUCCESS){
			serialSendBusy = TRUE;
		}*/
	}

	void service_search(ChannelState* state, uint8_t type){
	    DataPayload *new_dp = &(state->packet); 
	    clean_packet(new_dp);
	    dp_complete(new_dp, HOME_CHANNEL, HOME_CHANNEL, 
	             QUERY, sizeof(QueryMsg));
	    QueryMsg *q = (QueryMsg *) new_dp->data;
	    q->type = type;
	    strcpy(q->name, controller_name);
	    knot_broadcast(state, new_dp);
	    set_ticks(state, TICKS);
	    set_state(state, STATE_QUERY);
	    // Set timer to exit Query state after 5 secs~
	}

	void send(DataPayload *dp, int dest){
		DataPayload *payload = (DataPayload *) (call RadioAMSend.getPayload(&am_pkt, sizeof(DataPayload)));
		memcpy(payload, dp, sizeof(DataPayload));
		if (call RadioAMSend.send(dest, &am_pkt, sizeof(DataPayload)) == SUCCESS) sendBusy = TRUE;
		else {
			PRINTF("ID: %d, Radio Msg could not be sent, channel busy\n", TOS_NODE_ID);
			report_problem();
		}
	}

	void knot_broadcast(DataPayload *dp, ChannelState *state){
		increment_seq_no(state, dp);
		send(dp, AM_BROADCAST_ADDR);
	}











	 event void Boot.booted() {
        if (call RadioControl.start() != SUCCESS) report_problem();
        PRINTF("*********************\n****** BOOTED *******\n*********************\n");
        PRINTFFLUSH();
    }
/*-----------Radio & AM EVENTS------------------------------- */
    event void RadioControl.startDone(error_t error) {
        startTimer();
    }

    event void RadioControl.stopDone(error_t error) {}
/*----------------Security events -------------------------------*/
   
/*-----------Received packet event, main state event ------------------------------- */
    event message_t* RadioReceive.receive(message_t* msg, void* payload, uint8_t len) {
        DataPayload dp = (DataPayload *) payload;
		/* Gets data from the connection */
		uint8_t src;
		//if (!src) return; /* The cake was a lie */
	    uint8_t cmd = dp.hdr.cmd;
		PRINTF("KNoT>> Received packet from Thing: ");PRINTF("%d\n", src);
		PRINTF("Data is ");PRINTF(dp.dhdr.tlen);PRINTF(" bytes long\n");
		PRINTF("Received a ");PRINTF(cmdnames[cmd]);PRINTF(" command.\n");
		PRINTF("Message for channel ");PRINTF("%d\n", dp.hdr.dst_chan_num);
		
		switch(cmd){
			case(QUERY):   		query_handler(&dp, src);	return;
			//case(CONNECT): 		connect_handler(&dp, src);  return;
		}

		ChannelState *state = call ChannelTable.get_channel_state(dp.hdr.dst_chan_num);
		/* Always allow disconnections to prevent crazies */
		if (cmd == DISCONNECT) {
			if (state) {
				//remove_timer(state->timer);
				call ChannelTable.remove_channel(state->chan_num);
			}
			state = &home_channel_state;
			state->remote_addr = src; /* Rest of disconnect handled later */ 
		} else if (!state){
			PRINTF("Channel doesn't exist\n");
			return;
		} else if (!valid_seqno(state, &dp)){
			PRINTF("Old packet\n");
			return;
		}
		/* PUT IN QUERY CHECK FOR TYPE */
		switch(cmd){
			//case(CACK):   		cack_handler(state, &dp);	break;
			//case(PING):   		ping_handler(state, &dp);	break;
			//case(PACK):   		pack_handler(state, &dp);	break;
			//case(RACK):			rack_handler(state, &dp);	break;
			//case(DISCONNECT): 	close_handler(state, &dp);	break;
			default:			PRINTF("Unknown CMD type\n");
		}
		PRINTF("%d\n", "FINISHED.");
        report_received();
        
       
         PRINTF("----------\n");PRINTFFLUSH();
        return msg; /* Return packet to TinyOS */
        
    }
   /* event message_t* SerialReceive.receive(message_t* msg, void* payload, uint8_t len) {
    	return msg
    }
*/
    event void RadioAMSend.sendDone(message_t* msg, error_t error) {
        if (error == SUCCESS)
            report_sent();
        else
            report_problem();

        sendBusy = FALSE;
    }
/*
    event void SerialAMSend.sendDone(message_t* msg, error_t error) {
    if (error == SUCCESS)
        report_sent();
    else
        report_problem();

    sendBusy = FALSE;
    }
*/
    /*-----------LED Timer EVENTS------------------------------- */
    event void LEDTimer1.fired(){
        call Leds.led2Toggle();
    }

    event void LEDTimer0.fired(){
        call Leds.led0Toggle();
    }
    event void LEDTimer2.fired(){
        call Leds.led1Toggle();
    }

    /*-----------Sensor Events------------------------------- */
    event void LightSensor.readDone(error_t result, uint16_t data) {
        if (result != SUCCESS){
            data = 0xffff;
            report_problem();
        }
        light = data;
    }
    event void TempSensor.readDone(error_t result, uint16_t data) {
        if (result != SUCCESS){
            data = 0xffff;
            report_problem();
        }
        temp = data;
    }

}