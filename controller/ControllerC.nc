#include <string.h>
#include <stdlib.h>
#include "Timer.h"
#include "ChannelTable.h"
#include "ChannelState.h"
#include "KNoTProtocol.h"
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

#define HOME_CHANNEL 0

module ControllerC @safe()
{
    uses {
        interface Boot;
        interface AMPacket;
        interface SplitControl as RadioControl;
        interface AMSend;
        interface Receive;
        interface AMSend as SerialAMSend;
        interface Receive as SerialReceive;
        interface Timer<TMilli>;
        interface Timer<TMilli> as LEDTimer0;
        interface Timer<TMilli> as LEDTimer1;
        interface Timer<TMilli> as LEDTimer2;
        interface Read<uint16_t> as LightSensor;
        interface Read<uint16_t> as TempSensor;
        interface Leds;
        interface ChannelTable;
        interface ChannelState;
        interface KNoT;
    }
}
implementation
{
	bool sendBusy = FALSE;
	bool serialSendBusy = FALSE;
	nx_uint8_t temp;
    nx_uint8_t light;
	
	message_t serial_pkt;

	char controller_name[] = "The Boss";
	ChanState home_channel_state;
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
		

	void qack_handler(DataPayload *dp, uint8_t src) {
		DataPayload *pkt = (DataPayload *) (call SerialAMSend.getPayload(&serial_pkt, sizeof(DataPayload)));
		SerialQueryResponseMsg *qr;
	    ChanState *state = &home_channel_state;
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
		memcpy(pkt, dp, sizeof(DataPayload));
		if (call SerialAMSend.send(0, &serial_pkt, sizeof(DataPayload)) == SUCCESS){
			serialSendBusy = TRUE;
		}
	}

	void service_search(ChanState* state, uint8_t type){
		DataPayload *new_dp;
		QueryMsg *q = (QueryMsg *) new_dp->data;
	    new_dp = &(state->packet); 
	    clean_packet(new_dp);
	    call KNoT.dp_complete(new_dp, HOME_CHANNEL, HOME_CHANNEL, 
	             QUERY, sizeof(QueryMsg));
	    q->type = type;
	    strcpy((char*)q->name, controller_name);
	    call KNoT.knot_broadcast(state, new_dp);
	    //set_ticks(state, TICKS);
	    set_state(state, STATE_QUERY);
	    // Set timer to exit Query state after 5 secs~
	}

	
	event void Boot.booted() {
		PRINTF("*********************\n****** BOOTED *******\n*********************\n");
        PRINTFFLUSH();
    }
/*-----------Radio & AM EVENTS------------------------------- */
    event void RadioControl.startDone(error_t error) {}

    event void RadioControl.stopDone(error_t error) {}
/*----------------Security events -------------------------------*/
   
/*-----------Received packet event, main state event ------------------------------- */
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
    	ChanState *state;
        DataPayload *dp = (DataPayload *) payload;
		/* Gets data from the connection */
		uint8_t src = 0;
		//if (!src) return; /* The cake was a lie */
	    uint8_t cmd = dp->hdr.cmd;
		PRINTF("KNoT>> Received packet from Thing: ");PRINTF("%d\n", src);
		PRINTF("Data is ");PRINTF("%d", dp->dhdr.tlen);PRINTF(" bytes long\n");
		PRINTF("Received a ");PRINTF(cmdnames[cmd]);PRINTF(" command.\n");
		PRINTF("Message for channel ");PRINTF("%d\n", dp->hdr.dst_chan_num);
		
		switch(cmd) { /* Drop packets for cmds we don't accept */
        case(QUERY):   return msg;
        case(CONNECT): return msg;
        case(QACK):    qack_handler(dp, src);return msg;
    	}
	    /* Grab state for requested channel */
		state = call ChannelTable.get_channel_state(dp->hdr.dst_chan_num);
		if (!state){ /* Attempt to kill connection if no state held */
			PRINTF("Channel ");PRINTF("%d", dp->hdr.dst_chan_num);PRINTF(" doesn't exist\n");
			state = &home_channel_state;
			state->remote_chan_num = dp->hdr.src_chan_num;
			state->remote_addr = src;
			//close_graceful(state);
			return msg;
		} else if (!call KNoT.valid_seqno(state, dp)) {
			PRINTF("Old packet\n");
			return msg;
		}

		switch(cmd) {
			//case(CACK):     	cack_handler(state, &dp);            break;
			//case(RESPONSE): 	response_handler(state, &dp);        break;
			//case(RSYN):		 	response_handler(state, &dp); send_rack(state); break;
			// case(CMDACK):   	command_ack_handler(state,dp);break;
			//case(PING):     	ping_handler(state, &dp);            break;
			//case(PACK):     	pack_handler(state, &dp);            break;
			//case(DISCONNECT):   disconnect_handler(state, &dp, src); break;
	        //case(DACK):                                              break;
			default: 			PRINTF("Unknown CMD type\n");
		}
		PRINTF("%s\n", "FINISHED.");
        report_received();
        PRINTF("----------\n");PRINTFFLUSH();
        return msg; /* Return packet to TinyOS */
    }
    event message_t* SerialReceive.receive(message_t* msg, void* payload, uint8_t len) {
    	return msg;
    }

    event void AMSend.sendDone(message_t* msg, error_t error) {
        if (error == SUCCESS) report_sent();
        else report_problem();

        sendBusy = FALSE;
    }

    event void SerialAMSend.sendDone(message_t* msg, error_t error) {
    if (error == SUCCESS)
        report_sent();
    else
        report_problem();

    sendBusy = FALSE;
    }

    event void Timer.fired(){
    }

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