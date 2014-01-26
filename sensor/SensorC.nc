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
	nx_uint8_t temp;
    nx_uint8_t light;
	ChanState home_chan;


	/*------------------------------------------------------- */

      
	/*------------------------------------------------- */
	
	event void Boot.booted() {
		PRINTF("*********************\n****** BOOTED *******\n*********************\n");
        PRINTFFLUSH();
        call ChannelTable.init_table();
        call ChannelState.init_state(&home_chan, 0);
        //call Timer.startPeriodic(5000);
    }

   
/*-----------Received packet event, main state event ------------------------------- */
    event message_t* KNoT.receive(uint8_t src, message_t* msg, void* payload, uint8_t len) {
    	ChanState *state;
        DataPayload *dp = (DataPayload *) payload;
		/* Gets data from the connection */
	    uint8_t cmd = dp->hdr.cmd;
		PRINTF("KNoT>> Received packet from Thing: %d\n", src);
		PRINTF("Data is %d bytes long\n", dp->dhdr.tlen);
		PRINTF("Received a %s command\n", cmdnames[cmd]);
		PRINTF("Message for channel %d\n", dp->hdr.dst_chan_num);
        PRINTFFLUSH();

        switch(cmd){
            case(QUERY): call KNoT.query_handler(&home_chan, dp, src); return msg;
            case(CONNECT): call KNoT.connect_handler(call ChannelTable.new_channel(), dp, src); return msg;
        }

        /* Grab state for requested channel */
        state = call ChannelTable.get_channel_state(dp->hdr.dst_chan_num);
        /* Always allow disconnections to prevent crazies */
        if (cmd == DISCONNECT) {
            if (state) {
                //remove_timer(state->timer);
                call ChannelTable.remove_channel(state->chan_num);
            }
            state = &home_chan;
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
            case(CACK):         call KNoT.cack_handler(state, dp);   break;
            case(PING):         call KNoT.ping_handler(state, dp);   break;
            case(PACK):         call KNoT.pack_handler(state, dp);   break;
            //case(RACK):         call KNoT.rack_handler(state, dp);   break;
            case(DISCONNECT):   call KNoT.close_handler(state, dp);  break;
            default:            PRINTF("Unknown CMD type\n");
        }
        PRINTF("FINISHED.\n");
        call LEDBlink.report_received();
        PRINTF("----------\n");PRINTFFLUSH();
        return msg; /* Return packet to TinyOS */
    }

    event void Timer.fired(){
        call KNoT.query(&home_chan, 1);
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