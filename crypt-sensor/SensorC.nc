#include <string.h>
#include <stdlib.h>
#include "Timer.h"
#include "ChannelTable.h"
#include "ChannelState.h"
#include "KNoTProtocol.h"
#include "KNoT.h"
#include "ECC.h"
#include "printf.h"

#if DEBUG
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

module SensorC @safe()
{
  uses {
    interface Boot;
    interface Timer<TMilli>;
    interface Timer<TMilli> as CleanerTimer;
    //interface Read<uint16_t> as LightSensor;
    interface Read<uint16_t> as TempSensor;
    interface LEDBlink;
    interface ChannelTable;
    interface ChannelState;
    interface KNoTCrypt as KNoT;
  }
}
implementation
{
  nx_uint16_t temp;
  nx_uint8_t light;
  ChanState home_chan;
  uint8_t testKey_size = 10;
  uint32_t nonce;
  Point publicKey = { .x = {0x5d75, 0xa416, 0x94f6, 0x703e, 0x7f9e, 0xf511, 0x3315, 0x3b73, 0x7ca8, 0x442b},
                      .y = {0xbf3e, 0xeeef, 0x7517, 0x1505, 0x4f20, 0x9bae, 0x3426, 0x5b00, 0x377c, 0xac91}
                    };
  Point pkc_signature = { .x = {0x6df6, 0x675b, 0x44d9, 0x3e11, 0xd26c, 0xb723, 0x5b14, 0x3b7d, 0x8fc1, 0xcfcc},
                          .y = {0x9ffb, 0xcba4, 0xf71c, 0xfed3, 0xbdda, 0xcca6, 0x15f0, 0x4f2e, 0xe17f, 0x69ad}
                        };
  uint16_t privateKey[11] = {0xbf3d, 0x27bd, 0x26a3, 0xa2d7, 0x1225, 0x2cc1, 0x7899, 0xd02d, 0x914c, 0x1382, 0x0000};
  /* Checks the timer for a channel's state, retransmitting when necessary */
  void check_timer(ChanState *state) {
    decrement_ticks(state);
    if (ticks_left(state)) return;
    if (attempts_left(state)) {
      if (in_waiting_state(state)) {
        call KNoT.send_on_chan(state, (PDataPayload *)&(state->packet));
      } else if (state->state == STATE_CONNECTED){ 
        state->state = STATE_RSYN;
        PRINTF("Set RSYN state\n");
      } else {
        call KNoT.ping(state); /* PING A LING LONG */
      }
      set_ticks(state, state->ticks * 2); /* Exponential (double) retransmission */
      decrement_attempts(state);
      PRINTF("CLN>> Attempts left %d\n", state->attempts_left);
      PRINTF("CLN>> Retrying packet...\n");
    } else {
      PRINTF("CLN>> CLOSING CHANNEL DUE TO TIMEOUT\n");
      call KNoT.close_graceful(state);
      call ChannelTable.remove_channel(state->chan_num);
    }
    PRINTFFLUSH();
  } 

  /* Run once every 20ms */
  void cleaner(){
    ChanState *state;
    int i = 1;
    for (; i < CHANNEL_NUM; i++) {
      state = call ChannelTable.get_channel_state(i);
      //if (state) check_timer(state);
    }
  /*if (home_channel_state.state != STATE_IDLE) {
          check_timer(&home_channel_state);
          }*/
  }
        /*------------------------------------------------------- */
  ChanState *verify_pkc(PDataPayload *pdp, uint8_t src){
    /*Assume most certificates will be good */
    ChanState *state = call ChannelTable.new_channel(); 
    if (call KNoT.asym_pkc_handler(state, pdp) != VALID_PKC) {
      call ChannelTable.remove_channel(state->chan_num);
      return 0;
    }
    state->remote_addr = src;
    state->remote_chan_num = pdp->ch.src_chan_num;
    state->seqno = pdp->dp.hdr.seqno;
    return state;
  }

  ChanState *retrieve_state(uint8_t chan, ChanHeader *ch, PDataPayload *pdp, uint8_t src){
    ChanState *state = call ChannelTable.get_channel_state(chan);
    if (!state){ /* Attempt to kill connection if no state held */
      PRINTF("Channel %d doesn't exist\n", chan);
      state = &home_chan;
      state->remote_chan_num = ch->src_chan_num;
      state->remote_addr = src;
      state->seqno = pdp->dp.hdr.seqno;
      call KNoT.close_graceful(state);
      return NULL;
    } 
    else return state;
  }

        /*------------------------------------------------- */

  event void Boot.booted() {
    PRINTF("****** SENSOR BOOTED *******\n");
    PRINTFFLUSH();
    call LEDBlink.report_problem();
    call ChannelTable.init_table();
    call ChannelState.init_state(&home_chan, 0);
    call CleanerTimer.startPeriodic(TICK_RATE);
    call KNoT.init_asymmetric(privateKey, &publicKey, &pkc_signature);
  }

  void setup_sensor(uint8_t connected){
    if (!connected) return;
    call Timer.startPeriodic(5000);
  }

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
    call LEDBlink.report_received();
    PRINTF("SEC>> Received %s packet\n", is_symmetric(p->flags)?"Symmetric":
                                         is_asymmetric(p->flags)?"Asymmetric":"Plain");
    /* SYMMETRIC RECEIVE AND DECRYPT */
    if (is_symmetric(p->flags)) {
      sp = (SSecPacket *) p;
      PRINTF("SEC>> IV: %d\n", sp->flags & (0xff >> 2));PRINTFFLUSH();
      if (sp->ch.dst_chan_num) { /* Get state for channel */ 
        state = retrieve_state(sp->ch.dst_chan_num, &(sp->ch), pdp, src);
        if (!state) return msg;
      } else state = &home_chan;
      call KNoT.receiveDecrypt(state, sp, len, &valid);
      if (!valid) return msg; /* Return if decryption failed */
      pdp = (PDataPayload *) (&sp->ch); /* Offsetting to start of pdp */
    } /* ASYMMETRIC RECIEVE, DECRYPT AND PROCESS */
    else if (is_asymmetric(p->flags)) {
      if (!isAsymActive()) return msg; /* Don't waste time/energy */
      pdp = (PDataPayload *) &(p->ch);
      if (pdp->dp.hdr.cmd == ASYM_QUERY){
        PRINTF("Received query\n");PRINTFFLUSH();
        state = verify_pkc(pdp, src);
        if (!state) return msg;
        call KNoT.send_asym_resp(state);
        set_state(state, STATE_ASYM_RESP);
      }
      else if (pdp->dp.hdr.cmd == ASYM_RESP_ACK){
        PRINTF("Received response ack\n");PRINTFFLUSH();
        state = call ChannelTable.get_channel_state(pdp->ch.dst_chan_num);
        if (!state) return msg;
        state->remote_chan_num = pdp->ch.src_chan_num;
        nonce = call KNoT.asym_request_key(state);
        set_state(state, STATE_ASYM_REQ_KEY);
      }
      else if (pdp->dp.hdr.cmd == ASYM_KEY_RESP){
        state = call ChannelTable.get_channel_state(pdp->ch.dst_chan_num);
        if (call KNoT.asym_key_resp_handler(state, pdp, nonce)) {
          call KNoT.init_symmetric(state, state->key, SYM_KEY_SIZE);
          call KNoT.sym_handover(state);
        }
      }
      PRINTF("returning...\n"); PRINTFFLUSH();
      return msg;
    } /* PLAIN PACKET */
    else {
      pdp = (PDataPayload *) &(p->ch);
      /* Grab state for requested channel */
      state = retrieve_state(sp->ch.dst_chan_num, &(pdp->ch), pdp, src);
      if (!state) return msg;
    }
    ch = &(pdp->ch);
    cmd = pdp->dp.hdr.cmd;
    PRINTF("CON>> Received %s from Thing: %d for chan %d \n", cmdnames[cmd], src,
                                                              ch->dst_chan_num);
    PRINTFFLUSH();

    switch(cmd) { /* Drop packets for cmds we don't accept */
      case(QUERY): call KNoT.query_handler(&home_chan, pdp, src); return msg;
      case(CONNECT): call KNoT.connect_handler(state, pdp, src); return msg;
      case(QACK): return msg;
      case(DACK): return msg;
      case(SYM_HANDOVER): return msg;
    }
    if (!call KNoT.valid_seqno(state, pdp)) {
      PRINTF("Old packet\n");
      return msg;
    }
    switch(cmd) {
      case(CACK): setup_sensor(call KNoT.sensor_cack_handler(state, pdp)); break;
      case(PING): call KNoT.ping_handler(state, pdp); break;
      case(PACK): call KNoT.pack_handler(state, pdp); break;
      case(RACK): call KNoT.rack_handler(state, pdp); break;
      case(DISCONNECT): {
        call KNoT.disconnect_handler(state, pdp); 
        call Timer.stop();
        break;
      }
      default: PRINTF("Unknown CMD type\n");
    }
    call LEDBlink.report_received();
    return msg; /* Return packet to TinyOS */
  }

  event void Timer.fired(){
    call TempSensor.read();
  }



  /*-----------Sensor Events------------------------------- */
  /*event void LightSensor.readDone(error_t result, uint16_t data) {
    if (result != SUCCESS){
      data = 0xffff;
      call LEDBlink.report_problem();
    }
    light = data;
  }*/
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

  event void CleanerTimer.fired(){
    cleaner();
  }

}