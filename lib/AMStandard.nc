// $Id: AMStandard.nc,v 1.15 2003/10/07 21:46:36 idgay Exp $

/*									tab:4
 * "Copyright (c) 2000-2003 The Regents of the University  of California.  
 * All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 * 
 * IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE UNIVERSITY OF
 * CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 *
 * Copyright (c) 2002-2003 Intel Corporation
 * All rights reserved.
 *
 * This file is distributed under the terms in the attached INTEL-LICENSE     
 * file. If you do not find these files, copies can be found by writing to
 * Intel Research Berkeley, 2150 Shattuck Avenue, Suite 1300, Berkeley, CA, 
 * 94704.  Attention:  Intel License Inquiry.
 */
/*
 *
 * Authors:		Jason Hill, David Gay, Philip Levis
 * Date last modified:  6/25/02

 * MiniSec Authors:     Ghita Mezzour, Mark Luk
 * Date last modified:  2/17/08
 *
 */

//This is an AM messaging layer implementation that understands multiple
// output devices.  All packets addressed to TOS_UART_ADDR are sent to the UART
// instead of the radio.


/**
 * @author Jason Hill
 * @author David Gay
 * @author Philip Levis
 * @author Mark Luk
 */

includes NonceMsg;
includes CtrResyncMsg;
includes IntMsg;
module AMStandard
{
  provides {
    interface StdControl as Control;
    
    // The interface are as parameterised by the active message id
    interface SendMsg[uint8_t id];
    interface ReceiveMsg[uint8_t id];

    // How many packets were received in the past second
    command uint16_t activity();
  }

  uses {
    // signaled after every send completion for components which wish to
    // retry failed sends
    event result_t sendDone();

    interface StdControl as UARTControl;
    interface BareSendMsg as UARTSend;
    interface ReceiveMsg as UARTReceive;

    interface StdControl as RadioControl;
    interface BareSendMsg as RadioSend;
    interface ReceiveMsg as RadioReceive;
    interface StdControl as TimerControl;
    interface Timer as ActivityTimer;
    interface PowerManagement;
    interface OcbMode as cipherMode;
    //    interface Leds;
  }
}
implementation
{
  bool state;
  bool pendingSendToBS;/* debugging purpose */
  TOS_MsgPtr buffer;
  uint16_t lastCount;
  uint16_t counter;
  uint8_t blockSize = 8;
  uint8_t keySize = 10;
  uint8_t preCombBlocks = 5;
  uint8_t tagLength = 4;
  CipherModeContext cc;
  uint8_t key[] = {0x05,0x15,0x25,0x35,0x45,0x55,0x65,0x75,0x85,0x95};
  uint8_t decryptedMsg[]= {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00};
  uint8_t iv[]= {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00};

  uint8_t plainMsg[]= {0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08, 0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0x10, 0x11,0x12,0x13,0x14,0x15,0x16 };
  uint8_t cipherMsg[]= {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
  uint8_t tag[]={0x00,0x00,0x00,0x00};
  uint8_t message_decrypted[]= {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
  uint8_t cipher_rec[]= {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
  uint8_t tag_rec[]= {0x00, 0x00, 0x00, 0x00};
  uint8_t tag_length = 4;
  uint8_t max_times_inc_IV;
  uint8_t nbre_times_inc_IV = 0;
  TOS_Msg dataToSendToBS;
  uint8_t nbreLB;
  /*
   * number of consecutive failure of decrypting a message even
   * after the IV was incremented max_times_inc_IV
   */
  uint8_t num_f;
  /* 
   * number of times, the receiver fails to decrypt messages, before      
   * it runs the resync protocol
   */
  uint8_t num_fb_resync; 
  TOS_MsgPtr buffer_nonce;

  TOS_MsgPtr data_nonce;
  uint8_t waiting_for_resync;


  /* testing purpose */
  uint8_t cipherTest[]= {0,0xb7,0xf,0xc4,0x13,0x71,0xfd,0x95,0x36,0x3f,0x40,0xea,0xeb,0x9a,0x60,0x88,0x24,0xcc,0x2b,0xd9,0x3c,0xfe};
  uint8_t tagTest[]={0x73, 0xd9, 0x54, 0x7f};
  // void dumpInt ( uint8_t int_name, uint8_t value) ;
  void dumpBuffer (char * bufName, uint8_t * buf, uint8_t size);
  // void dumpHexa ( uint8_t hexaName, uint8_t value);
  // Initialization of this component

  /* helping functions */
  int IncIV(uint8_t *IV, uint8_t inc);
  int incIV(uint8_t *IV);

  void DecIV(uint8_t *IV, uint8_t dec);
  void decIV(uint8_t *IV);

  void cpyBuffer(uint8_t *des, uint8_t *src, uint8_t size);

  command bool Control.init() {
    result_t ok1, ok2;

    call TimerControl.init();
    ok1 = call UARTControl.init();
    ok2 = call RadioControl.init();
    
    call cipherMode.init(&cc, keySize, key, tagLength, preCombBlocks); 
    
    state = FALSE;
    lastCount = 0;
    counter = 0;
    nbreLB = 1;
    nbre_times_inc_IV = 0;
    max_times_inc_IV= 1;
    //max_times_inc_IV= 100;
    dbg(DBG_BOOT, "AM:   Module initialized\n");
    num_f = 0;
    num_fb_resync= 4;
    /*
     * I assume that the nodes are initially syncronized,
     * and that the node will wait for resync only if it
     * is not able to decrypt too many msgs.
     * The real protocol requires that the sender sends the
     * counter value to the receiver, before it starts sending
     * it other messages.
     * in practice, this means we need to reboot both nodes b4 starting
     */
    waiting_for_resync=0;

    return rcombine(ok1, ok2);
  }

  // Command to be used for power managment
  command bool Control.start() {
    result_t ok0 = call TimerControl.start();
    result_t ok1 = call UARTControl.start();
    result_t ok2 = call RadioControl.start();
    result_t ok3 = call ActivityTimer.start(TIMER_REPEAT, 1000);

    //HACK -- unset start here to work around possible lost calls to 
    // sendDone which seem to occur when using power management.  SRM 4.4.03
    state = FALSE;

    call PowerManagement.adjustPower();

    return rcombine4(ok0, ok1, ok2, ok3);
  }

  
  command bool Control.stop() {
    result_t ok1 = call UARTControl.stop();
    result_t ok2 = call RadioControl.stop();
    result_t ok3 = call ActivityTimer.stop();
    // call TimerControl.stop();
    call PowerManagement.adjustPower();
    return rcombine3(ok1, ok2, ok3);
  }

  command uint16_t activity() {
    return lastCount;
  }
  
  void dbgPacket(TOS_MsgPtr data) {
    uint8_t i;

    for(i = 0; i < sizeof(TOS_Msg); i++)
      {
	dbg_clear(DBG_AM, "%02hhx ", ((uint8_t *)data)[i]);
      }
    dbg_clear(DBG_AM, "\n");
  }

  // Handle the event of the completion of a message transmission
  result_t reportSendDone(TOS_MsgPtr msg, result_t success) {
    state = FALSE;
    signal SendMsg.sendDone[msg->type](msg, success);
    signal sendDone();

    return SUCCESS;
  }

  event result_t ActivityTimer.fired() {
    lastCount = counter;
    counter = 0;
    return SUCCESS;
  }
  
  default event result_t SendMsg.sendDone[uint8_t id](TOS_MsgPtr msg, 
						      result_t success) {
    return SUCCESS;
  }
  default event result_t sendDone() {
    return SUCCESS;
  }

  // This task schedules the transmission of the Active Message
  task void sendTask() {
    result_t ok;
    TOS_MsgPtr buf;
    buf = buffer;
    if (buf->addr == TOS_UART_ADDR)
      ok = call UARTSend.send(buf);
    else
      ok = call RadioSend.send(buf);

    if (ok == FAIL) // failed, signal completion immediately
      reportSendDone(buffer, FAIL);
  }

  // Command to accept transmission of an Active Message
  command result_t SendMsg.send[uint8_t id](uint16_t addr,
					    uint8_t length, 
					    TOS_MsgPtr data) {
    //IntMsg *message;
    //uint8_t valid=0;
    if (!state) {      
      dumpBuffer("=>gm IV_sending", iv+7,1);
      dumpBuffer("data->data plain *radio*", data->data, length);
      //encrypt(context, plaintext, ciphertest, tag, numButes, IV
      //now cipherMsg has ciphertext, tag has tag 
      call cipherMode.encrypt(&cc, data->data, cipherMsg, tag, length, iv);
      dumpBuffer("data->data cipher *radio*", data->data, length);
      dumpBuffer("tag *radio* ", tag, tag_length);
      
      //copies ciphertext and tag into data->data
      cpyBuffer(data->data, cipherMsg, length);
      cpyBuffer((data->data)+length, tag, tag_length);

      /* 
       * TODO: small pbm
       * every thing is done in bytes, so even if only 3 LB bits are sent
       * the max length of the msg is reduced by 1 byte
       * I am sending one more byte over the air, but actually taking advantage
       * of only two bits (this is just a hack, actually I need to find a way
       * to send only more few bits)
       */
      data->data[length+tag_length] = iv[7] & (0xff >> (8-nbreLB));
      
      dumpBuffer("doit marcher send", data->data, sizeof(data->data));
      
      /* as the tag is also sent, the max length of the msgs is reduced by tag_length */
      state = TRUE;
      if ((length+tag_length+1) > DATA_LENGTH) { /* the 1 is for LB */
        dbg(DBG_AM, "AM: Send length too long: %i. Fail.\n", (int)length);
        state = FALSE;
        return FAIL;
      }
      if (!(post sendTask())) {
      	dbg(DBG_AM, "AM: post sendTask failed.\n");
      	state = FALSE;
      	return FAIL;
      }
      else {
      	buffer = data;
      	data->length = length+tag_length+1; /* the 4 is from the tag_length, the 1 is for LB */
      	data->addr = addr;
      	data->type = id;
      	buffer->group = TOS_AM_GROUP;
      	dbg(DBG_AM, "Sending message: %hx, %hhx\n\t", addr, id);
      	dbgPacket(data);
      	/* 
      	 *increment the IV 
      	 * the increment would fail if the complete space for the IV
      	 * was used.
      	 * There is a need to rekey. Otherwise we won't have semantic
      	 * security.
      	 */
      	if(!incIV(iv))
          return FAIL;
      }
      dbg(DBG_BOOT, "=>gm AM:msg sent\n");
      return SUCCESS;
    }
    return FAIL;
  }

  event result_t UARTSend.sendDone(TOS_MsgPtr msg, result_t success) {
    return reportSendDone(msg, success);
  }
  event result_t RadioSend.sendDone(TOS_MsgPtr msg, result_t success) {
    return reportSendDone(msg, success);
  }
  /*
  event result_t RadioSendToBS.sendDone(TOS_MsgPtr msg, result_t success) {
    return reportSendDone(msg, success);
  }
  */

  // Handle the event of the reception of an incoming message
  
  TOS_MsgPtr received(TOS_MsgPtr packet)  __attribute__ ((C, spontaneous)) {

    uint16_t addr = TOS_LOCAL_ADDRESS;
    uint8_t valid = 0;
    uint8_t i=0, j;
    uint8_t iv_current[8];
    uint8_t low_mask = 0xff >>(8- nbreLB);
    uint8_t up_mask = 0xff << nbreLB;
    uint8_t inc =  1 << nbreLB;
    uint8_t enc_msg_length = (packet->length)-tag_length-1; /* the 1 is for the LB */
    //uint8_t resync_succ = 1;
    /*                             
     * TODO: generate a real nonce each time we need to resync
     */
    //uint16_t nonce = 0x19c3;

    //uint8_t iv_nonce[8] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00};
    //NonceMsg nonce_msg;
    TOS_Msg nonce_msg, ctr_msg;
    dbg(DBG_BOOT, "=>gm AM:msg received\n");

     /*
     * the node we are communicating with, wants us
     * to send it our current counter, because it
     * wasn't able to decrypt too many consecutive 
     * messages.
     */
    
    if (packet->type == AM_NONCEMSG) { 
      if(!state) {
      	state = TRUE;
      	if(!post sendTask()) {
      	  state = FALSE;
      	}
      	else {
      	  buffer= &ctr_msg;
      	  buffer->type= AM_CTRRESYNCMSG ;
      	  buffer->group = TOS_AM_GROUP;
      	  buffer->length = sizeof(CtrResyncMsg_t);  
      	  for (j = 0; j < 8; j++)
      	    buffer->data[j] = iv[j];
      	} 
      }
      return packet;
    }
    //received a counter resynch message from the sender
    // set iv to whatever it got over the message
    if (packet->type == AM_CTRRESYNCMSG){
      for(j=0; j < 8; j++)
        iv[j] = packet->data[j];
      return packet;
    }
    /*
      uint8_t plain_ctr[9]; 
      dbg(DBG_AM, "AM resync: nonce msg received \n ");
      for(i=0; i<8; i++) {
	plain_ctr[i] = iv[i];
      }
      plain_ctr[8] = nonce;
    */

      /*
       * the length for the encryption is 8+length of the nonce
       */

    /*
      call cipherMode.encrypt(&cc, plain_ctr, cipherMsg, tag, 9, iv_nonce);
    }

    else {
    */
      for (i=0; i< enc_msg_length; i++)
	cipher_rec[i] = (packet->data)[i];
      for (i=0; i<tag_length; i++)
	tag_rec[i]= (packet->data)[i+enc_msg_length];
      
      /*
      dumpBuffer("rec", packet->data, sizeof(packet->data));
    */

      /*
       * we received a ctr resync msg, 
       * we need to update our counter to the counter received.
       */    
      

    /*
      if(packet->type == AM_CTRRESYNCMSG ) {
	dbg(DBG_AM, "AM resync: ctr resync msg received \n ");
	call cipherMode.decrypt(&cc, cipher_rec+8, tag_rec, message_decrypted, enc_msg_length-8, iv_nonce, &valid);
	if(valid) {
	  if(*(message_decrypted+8)==nonce) {
	    for (i=0; i<8; i++) {
	      if(*(message_decrypted+8+i) != cipher_rec[i]) {
		resync_succ =0;
	      }
	  }
	  if(resync_succ) {
	    waiting_for_resync = 0;
    */
	    /*
	     * here we could check that the IV that was received is of a higher
	     * value than the current iv.
	     * If it is not, we would realize that a resync happened even if 
	     * it wasn't needed, so maybe we are under attack.
	          */
    /*
	    for(i=0; i<8; i++) {
	      iv[i] = *(message_decrypted+8+i);
	    }
	  }
	}
      }
    }
    
    */

      /*
       * if we are waiting for the ctr resync, then we know that
       * our counter and the counter of the receiver are
       * out of sync, so we can be sure that we won't be able 
       * to decrypt, so we shouldn't waste our energy on that.
       */
      /* else   if(!waiting_for_resync) { */ 
    //	dbg(DBG_AM, "AM resync: msg received, no resync \n");
	/*
	 * taking advantage of the LB
	 */
	
	//dumpBuffer("dump pkt received IV  ",packet->data,  4 + tag_length + 1);
    cpyBuffer(iv_current, iv, 8);

    dumpBuffer("IV rec curr ", iv+7, 1);
    iv[7] = ((iv[7] & up_mask  ) | 
	     (packet->data[enc_msg_length +tag_length] & low_mask ));
	
    if((iv_current[7] & low_mask) >((packet->data[enc_msg_length +tag_length])&low_mask) ) {
      IncIV(iv, inc);
    }
    
    /*
     * we try to decrypt the message with the current iv, and if
     * we fail, we inc the iv by inc, and we try to decrypt again
     * If at a certain time before max_times_inc_IV, we are able to 
     * decrypt the msg, then we are happy.
     * If not, we need to set the iv to the one before our multiple
     * incrementations, and increment the num_f, so that we run
     * the resync protocol if there are too many successive failures
     * of the decryption.
     */
    
    while((!valid) && nbre_times_inc_IV< max_times_inc_IV ) {
      dbg(DBG_BOOT, "=>gm trying to decrypt \n");
      dumpBuffer("=>gm IV_reception tried ", iv+7, 1);
      call cipherMode.decrypt(&cc, cipher_rec, tag_rec, message_decrypted, enc_msg_length, iv, &valid);
      IncIV(iv, inc);
      nbre_times_inc_IV ++;
    }
	
    /* 
     * We were able to decrypt the msg
     */
    if (valid) {
      dbg(DBG_BOOT, "=>gm AM: msg decrypted\n");
      num_f =0;
      cpyBuffer(packet->data, message_decrypted, enc_msg_length);

      DecIV(iv, inc);
      nbre_times_inc_IV = 0;
      dumpBuffer("data->data decrypted *radio*", message_decrypted, enc_msg_length);
	 
      counter++;
      dbg(DBG_BOOT, "AM_address = %hx, %hhx; counter:%i\n", packet->addr, packet->type, (int)counter);
      
      if ((packet->crc == 1 && packet->group == TOS_AM_GROUP) &&
      	  (packet->addr == TOS_BCAST_ADDR || packet->addr == addr)) {
    	  uint8_t type = packet->type;
    	  TOS_MsgPtr tmp;
    	  // Debugging output
    	  dbg(DBG_BOOT, "Received message:\n\t");
    	  dbgPacket(packet);
    	  dbg(DBG_BOOT, "AM_type = %d\n", type);
    	  
    	  // dispatch message
    	  tmp = signal ReceiveMsg.receive[type](packet);
    	  if (tmp) 
    	    packet = tmp;
    	}
          
          return packet;
    }
    else {
      dbg(DBG_BOOT, "=>gm AM resync: msg not decrypted \n");
      num_f++;
      
      nbre_times_inc_IV=0;
       dbg(DBG_BOOT, "=>gm not decrypted  num_f %d \n", num_f);
      /*
       * we weren't able to decrypt too many consecutive messages, most
       * probably, our counter is out of sync with the counter
       * of the sender, we should run the resync protocol.
       */


      if(num_f == num_fb_resync) {
	dbg(DBG_BOOT, "=>gm need to resync \n");
	num_f = 0;
	/*
	 * we need to resync, send a nonce to the sender
	 */
	// nonce_msg.nonce = nonce;
	/*
	 * TODO, probably need to send the nonce only to the node
	 * we are communicating with, and not to TOS_BCAST_ADDR.
	 * the prblem is the src addr is not specified in all the 
	 * types of msgs, so how to know who sent us this msg. 
	 */
	if(!state) {
	  state = TRUE;
	  if(!post sendTask()) {
	    state = FALSE;
	  }
	  else {
	    //send nonce to sender, requesting a resynch
	    buffer = &nonce_msg;
	    buffer->type = AM_NONCEMSG;
	    buffer->group = TOS_AM_GROUP;	    
	    buffer->length = sizeof(NonceMsg_t);
	    buffer->addr = TOS_BCAST_ADDR;
	    return packet;
	  }
	}
      }
	  
       /*
	* if none of the IVs tried matches, the msg received was probably
	* just garbage, (or maybe the IV is out of sync with sender, we
	* deal with that in a separate case.) 
	* reset the iv to the one before the incrementations.
	*/
      for (i=0; i<8; i++) {
        iv[i] = iv_current[i];
      }
       /*
	* justing setting the packet data to 0
	* so that if it doesn't decrypt correctly
	* I get 0 and not any garbage, should be removed
	* eventually.
	*/
       
      for (i=0; i<enc_msg_length; i++)
        packet->data[i] = 0;
       

       /*
	* if the decryption wasn't successful, the packet shouldn't be
	* returned to the application, but if I don't do so, the application
	* gets a segfault
	*/
       return packet;
    }
  }
  

  
  // default do-nothing message receive handler
    default event TOS_MsgPtr ReceiveMsg.receive[uint8_t id](TOS_MsgPtr msg) {

    dbg(DBG_BOOT, "=>gm : event msg received: ReceiveMsg.receive \n");

    return msg;
  }

  event TOS_MsgPtr UARTReceive.receive(TOS_MsgPtr packet) {
    // A serial cable is not a shared medium and does not need group-id
    // filtering
    dbg(DBG_BOOT, "=>gm: event msg received: UARTReceive.receive \n");

    packet->group = TOS_AM_GROUP;
    
    return received(packet);
  }
  event TOS_MsgPtr RadioReceive.receive(TOS_MsgPtr packet) {
    
    dbg(DBG_BOOT, "=>gm: event msg received: RadioReceive.receive \n");
    return received(packet);
  }


   void dumpBuffer (char * bufName, uint8_t * buf, uint8_t size)
    {
      uint8_t b = 0;
      // fixme watch buffer overrun
      //char tmp[512];
      
      for (; b < size; b++) {
        dbg(DBG_USR1, "=>%s: 0x%x \n", bufName, buf[b] & 0xff);
      }
      dbg(DBG_USR1, "/n");
      //dbg(DBG_USR1, "%s: {%s}\n", bufName, tmp);
    }
   /*   
   void dumpInt ( uint8_t int_name, uint8_t value) {
     dbg("%s: %d \n", int_name , value);
   }
   */


   int IncIV(uint8_t *IVr, uint8_t inc) {
     uint8_t i;
     for(i=0; i<inc; i++) {
       if(!incIV(IVr))
	 return 0;
     }
     return 1;
   }


   int incIV(uint8_t *IVs) {
     uint8_t i;
     uint8_t b=7;
     int cont_inc = 1;
     do {
       IVs[b]++;
       for(i=b; i<8; i++) {
	 if(IVs[i]) {
	   cont_inc = 0;
	 }
       }
       /*
        * the complete space for the IV was used
	* failure of the increment
	*/
       if((!b) && cont_inc) {
	 return 0;
       }
       b--;
     }
     while(cont_inc);
     return 1;
   }


   /*
    * In this code, the IV is decremented by dec only 
    * in the case after it was incremented by the same
    * value. That's why the decrementing of the IV will
    * always succeed and give a positive value.
    */
   void DecIV(uint8_t *IV, uint8_t dec) {
     uint8_t i;
     for (i=0; i<dec; i++) {
       decIV(IV);
     }
   }

   void decIV(uint8_t *IV) {
     uint8_t b=7;
     while(~b) {
       if(IV[b]) {
	 IV[b]--;
	 return;
       }	       
       IV[b] = ~0;
       b--;
     }
      
   }

   void cpyBuffer(uint8_t *des, uint8_t *src, uint8_t size) {
     uint8_t i;
     for(i=0; i<size; i++) {
       des[i] = src[i];
     }
   }

}
