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
#define SERIAL_SEARCH 1
#define SERIAL_CONNECT 2

module ControllerC @safe()
{
    uses {
        interface Boot;
        interface AMPacket;
        interface SplitControl as RadioControl;
        interface SplitControl as SerialControl;
        interface AMSend;
        interface Receive;
        interface AMSend as SerialSend;
        interface Receive as SerialReceive;
        interface Timer<TMilli>;
        interface LEDBlink;
        interface ChannelTable;
        interface ChannelState;
        interface KNoT;
    }
}
implementation
{
	bool sendBusy = FALSE;
	bool serialSendBusy = FALSE;
	ChanState home_chan;
	int serial_ready = 0;
	char buf[50];
	int serial_index = 0;


	/*------------------------------------------------------- */

      
	/*------------------------------------------------- */
	
	event void Boot.booted() {
		PRINTF("*********************\n****** BOOTED *******\n*********************\n");
        PRINTFFLUSH();
    }
/*-----------Radio & AM EVENTS------------------------------- */
    event void RadioControl.startDone(error_t error) {}

    event void RadioControl.stopDone(error_t error) {}
 	event void SerialControl.startDone(error_t error) {}

    event void SerialControl.stopDone(error_t error) {}

	//ChanState * new_state = call ChannelTable.new_channel();

   
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
        case(QACK):    call KNoT.qack_handler(&home_chan, dp, src);return msg;
    	}
	    /* Grab state for requested channel */
		state = call ChannelTable.get_channel_state(dp->hdr.dst_chan_num);
		if (!state){ /* Attempt to kill connection if no state held */
			PRINTF("Channel ");PRINTF("%d", dp->hdr.dst_chan_num);PRINTF(" doesn't exist\n");
			state = &home_chan;
			state->remote_chan_num = dp->hdr.src_chan_num;
			state->remote_addr = src;
			//close_graceful(state);
			return msg;
		} else if (!call KNoT.valid_seqno(state, dp)) {
			PRINTF("Old packet\n");
			return msg;
		}

		switch(cmd) {
			case(CACK):     	call KNoT.cack_handler(state, dp);            break;
			case(RESPONSE): 	call KNoT.response_handler(state, dp);        break;
			case(RSYN):		 	call KNoT.response_handler(state, dp); call KNoT.send_rack(state); break;
			// case(CMDACK):   	command_ack_handler(state,dp);break;
			case(PING):     	call KNoT.ping_handler(state, dp);            break;
			case(PACK):     	call KNoT.pack_handler(state, dp);            break;
			//case(DISCONNECT):   call KNoT.disconnect_handler(state, dp, src); break;
	        case(DACK):                                              break;
			default: 			PRINTF("Unknown CMD type\n");
		}
		PRINTF("%s\n", "FINISHED.");
        call LEDBlink.report_received();
        PRINTF("----------\n");PRINTFFLUSH();
        return msg; /* Return packet to TinyOS */
    }
    
    event message_t *SerialReceive.receive(message_t *msg, void* payload, uint8_t len){
    	DataPayload *dp = (DataPayload *)payload;
		uint8_t cmd = dp->hdr.cmd;
		PRINTF("SERIAL> Serial command received.\n");
		PRINTF("SERIAL> Packet length: %d", dp->dhdr.tlen);
		PRINTF("SERIAL> Message for channel %d", dp->hdr.dst_chan_num);

		switch (cmd) {
			case(SERIAL_SEARCH): call KNoT.query(&home_chan, ((QueryMsg*)dp)->type);break;
			case(SERIAL_CONNECT): call KNoT.connect(call ChannelTable.new_channel(), 
													((SerialConnect*)dp)->addr, 
													((SerialConnect*)dp)->rate);break;
		}
		call LEDBlink.report_received();
    	return msg;
    }

    event void AMSend.sendDone(message_t* msg, error_t error) {
        if (error == SUCCESS) call LEDBlink.report_sent();
        else call LEDBlink.report_problem();

        sendBusy = FALSE;
    }

    event void SerialSend.sendDone(message_t *msg, error_t error){
    	if (error == SUCCESS) call LEDBlink.report_sent();
        else call LEDBlink.report_problem();

        serialSendBusy = FALSE;
    }


    event void Timer.fired(){
    }
}