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

module SensorC @safe()
{
    uses {
        interface Boot;
        interface AMPacket;
        interface SplitControl as RadioControl;
        interface AMSend;
        interface Receive;
        interface Timer<TMilli>;
        interface Read<uint16_t> as LightSensor;
        interface Read<uint16_t> as TempSensor;
        interface LEDBlink;
        interface ChannelTable;
        interface ChannelState;
        interface KNoT;
    }
}
implementation
{
	bool sendBusy = FALSE;
	
	nx_uint8_t temp;
    nx_uint8_t light;
	ChanState home_channel_state;
	int serial_ready = 0;
	char buf[50];
	int serial_index = 0;
	int addr = 0;


	/*------------------------------------------------------- */

      
	/*------------------------------------------------- */
	
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
		
		switch(cmd){
            case(QUERY):        call KNoT.query_handler(dp, src);    return msg;
            case(CONNECT):      call KNoT.connect_handler(dp, src);  return msg;
        }
	    /* Grab state for requested channel */
		state = call ChannelTable.get_channel_state(dp->hdr.dst_chan_num);
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
            return msg;
        } else if (!call KNoT.valid_seqno(state, dp)){
            PRINTF("Old packet\n");
            return msg;
        }
        /* PUT IN QUERY CHECK FOR TYPE */
        switch(cmd){
            case(CACK):         cack_handler(state, dp);   break;
            case(PING):         ping_handler(state, dp);   break;
            case(PACK):         pack_handler(state, dp);   break;
            case(RACK):         rack_handler(state, dp);   break;
            case(DISCONNECT):   close_handler(state, dp);  break;
            default:            PRINT(F("Unknown CMD type\n"));
        }
		PRINTF("FINISHED.\n");
        call LEDBlink.report_received();
        PRINTF("----------\n");PRINTFFLUSH();
        return msg; /* Return packet to TinyOS */
    }
    

    event void AMSend.sendDone(message_t* msg, error_t error) {
        if (error == SUCCESS) call LEDBlink.report_sent();
        else call LEDBlink.report_problem();

        sendBusy = FALSE;
    }


    event void Timer.fired(){
    }

    

    /*-----------Sensor Events------------------------------- */
    event void LightSensor.readDone(error_t result, uint16_t data) {
        if (result != SUCCESS){
            data = 0xffff;
            call LEDBlink.report_problem();
        }
        light = data;
    }
    event void TempSensor.readDone(error_t result, uint16_t data) {
        if (result != SUCCESS){
            data = 0xffff;
            call LEDBlink.report_problem();
        }
        temp = data;
    }

}