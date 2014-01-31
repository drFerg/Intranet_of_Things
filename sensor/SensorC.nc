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
	nx_uint16_t temp;
    nx_uint8_t light;
	ChanState home_chan;



	/*------------------------------------------------------- */

      
	/*------------------------------------------------- */
	
	event void Boot.booted() {
		PRINTF("*********************\n****** BOOTED *******\n*********************\n");
        PRINTFFLUSH();
        call LEDBlink.report_problem();
        call ChannelTable.init_table();
        call ChannelState.init_state(&home_chan, 0);
        //call Timer.startOneShot(5000);
    }

    void setup_sensor(uint8_t connected){
        if (!connected) return;
        call Timer.startPeriodic(5000);

    }
   
/*-----------Received packet event, main state event ------------------------------- */
    event message_t* KNoT.receive(uint8_t src, message_t* msg, void* payload, uint8_t len) {
    	ChanState *state;
        DataPayload *dp = (DataPayload *) payload;
		/* Gets data from the connection */
	    uint8_t cmd = dp->hdr.cmd;
		PRINTF("SEN>> Received packet from Thing: %d\n", src);
		PRINTF("SEN>> Data is %d bytes long\n", dp->dhdr.tlen);
		PRINTF("SEN>> Received a %s command\n", cmdnames[cmd]);
		PRINTF("SEN>> Message for channel %d\n", dp->hdr.dst_chan_num);
        PRINTFFLUSH();

        switch(cmd){
            case(QUERY): call KNoT.query_handler(&home_chan, dp, src); return msg;
            case(CONNECT): call KNoT.connect_handler(call ChannelTable.new_channel(), dp, src); return msg;
            case(DACK): return msg;
        }

        /* Grab state for requested channel */
        state = call ChannelTable.get_channel_state(dp->hdr.dst_chan_num);
        /* Always allow disconnections to prevent crazies */
        if (!state){ /* Attempt to kill connection if no state held */
            PRINTF("Channel %d doesn't exist\n", dp->hdr.dst_chan_num);
            state = &home_chan;
            state->remote_chan_num = dp->hdr.src_chan_num;
            state->remote_addr = src;
            state->seqno = dp->hdr.seqno;
            call KNoT.close_graceful(state);
            return msg;
        } else if (!call KNoT.valid_seqno(state, dp)) {
            PRINTF("Old packet\n");
            return msg;
        }
        /* PUT IN QUERY CHECK FOR TYPE */
        switch(cmd){
            case(CACK): setup_sensor(call KNoT.sensor_cack_handler(state, dp)); break;
            case(PING): call KNoT.ping_handler(state, dp); break;
            case(PACK): call KNoT.pack_handler(state, dp); break;
            //case(RACK): call KNoT.rack_handler(state, dp); break;
            case(DISCONNECT):   call KNoT.disconnect_handler(state); call Timer.stop();break;
            default:            PRINTF("Unknown CMD type\n");
        }
        PRINTF("FINISHED.\n");
        call LEDBlink.report_received();
        PRINTF("----------\n");PRINTFFLUSH();
        return msg; /* Return packet to TinyOS */
    }

    event void Timer.fired(){
        call TempSensor.read();
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
        uint8_t t;
        if (result != SUCCESS){
            data = 0xffff;
            call LEDBlink.report_problem();
        }
        PRINTF("Data %d\n", data);
        temp = (float)-39.6 + (data * (float)0.01);
        t = temp;
        PRINTF("Temp: %d.%d\n", temp, temp>>2);
        PRINTF("Temp: %d\n", t);
        call KNoT.send_value(call ChannelTable.get_channel_state(1), &t, 1);
    }

}