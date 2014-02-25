#ifdef TEST_VECTOR
#define MSG_LEN 3
#else
#define MSG_LEN 52
#endif
includes CAPublicKey;
#define MAX_ROUNDS 10

module genPubPrivKeyCertM{
  uses{
    interface Boot;
    interface NN;
    interface ECC;
    interface ECDSA;
    interface Timer<TMilli> as myTimer;
    interface LocalTime<TMilli>;
    interface Random;
    interface Leds;
    interface AMSend as PubKeyMsg;
    interface AMSend as PriKeyMsg;
    interface AMSend as PacketMsg;
    interface AMSend as TimeMsg;
    interface SplitControl as SerialControl;
  }
}

implementation {
  message_t report;
  Point CAPublicKey;
  Point ClientPublicKey;
  NN_DIGIT ClientPrivateKey[NUMWORDS];
  NN_DIGIT CAPrivateKey[NUMWORDS];
  
  uint8_t message[MSG_LEN];
  NN_DIGIT r[NUMWORDS];
  NN_DIGIT s[NUMWORDS];
  uint8_t type;
  uint32_t t;
  uint8_t pass;
  uint16_t round_index;

  void init_data();
  void gen_PrivateKey();
  void ecc_init();
  void gen_PublicKey();
  void ecdsa_init();
  void sign();
  void verify();


  void init_data(){
#ifndef TEST_VECTOR
    uint8_t j;
#endif
    CAPrivateKey[10] = 0x0;
    CAPrivateKey[9] = 0x45FB;
    CAPrivateKey[8] = 0x58A9;
    CAPrivateKey[7] = 0x2A17;
    CAPrivateKey[6] = 0xAD4B;
    CAPrivateKey[5] = 0x1510;
    CAPrivateKey[4] = 0x1C66;
    CAPrivateKey[3] = 0xE74F;
    CAPrivateKey[2] = 0x277E;
    CAPrivateKey[1] = 0x2B46;
    CAPrivateKey[0] = 0x0866;
    memcpy(CAPublicKey.x, (NN_DIGIT *)&CA_PubKey_x, KEYDIGITS*NN_DIGIT_LEN);
    memcpy(CAPublicKey.y, (NN_DIGIT *)&CA_PubKey_y, KEYDIGITS*NN_DIGIT_LEN);
    pass = 0;
    t = 0;

    //init message
    memset(message, 0, MSG_LEN);
    //init private key
    memset(ClientPrivateKey, 0, NUMWORDS*NN_DIGIT_LEN);
    //init public key
    memset(ClientPublicKey.x, 0, NUMWORDS*NN_DIGIT_LEN);
    memset(ClientPublicKey.y, 0, NUMWORDS*NN_DIGIT_LEN);
    //init signature
    memset(r, 0, NUMWORDS*NN_DIGIT_LEN);
    memset(s, 0, NUMWORDS*NN_DIGIT_LEN);
    call ECC.init();
    
    gen_PrivateKey();
  }

  void gen_PrivateKey(){
    private_key_msg *pPrivateKey;
    call ECC.gen_private_key(ClientPrivateKey);
    //report private key
    pPrivateKey = (private_key_msg *)report.data;
    pPrivateKey->len = KEYDIGITS*NN_DIGIT_LEN;
    call NN.Encode(pPrivateKey->d, KEYDIGITS*NN_DIGIT_LEN, ClientPrivateKey, KEYDIGITS);
    call PriKeyMsg.send(1, &report, sizeof(private_key_msg));
  }

  void ecc_init(){
    uint32_t time_a, time_b;
    time_msg *pTime;

    type = 0;

    time_a = call LocalTime.get();

    call ECC.init();

    time_b = call LocalTime.get();

    t = time_b - time_a;

    pTime = (time_msg *)report.data;
    pTime->type = 0;
    pTime->t = t;
    pTime->pass = 0;
    call TimeMsg.send(1, &report, sizeof(time_msg));
  }

  void gen_PublicKey(){
    uint32_t time_a, time_b;
    public_key_msg *pPublicKey;

    type = 1;

    time_a = call LocalTime.get();

    //call ECC.win_mul_base(&PublicKey, PrivateKey);
    call ECC.gen_public_key(&ClientPublicKey, ClientPrivateKey);
    
    time_b = call LocalTime.get();

    t = time_b - time_a;

    pPublicKey = (public_key_msg *)report.data;
    pPublicKey->len = KEYDIGITS*NN_DIGIT_LEN;
    call NN.Encode(pPublicKey->x, KEYDIGITS*NN_DIGIT_LEN, ClientPublicKey.x, KEYDIGITS);
    call NN.Encode(pPublicKey->y, KEYDIGITS*NN_DIGIT_LEN, ClientPublicKey.y, KEYDIGITS);
    call PubKeyMsg.send(1, &report, sizeof(public_key_msg));
    
  }

  void ecdsa_init(){
    uint32_t time_a, time_b;
    time_msg *pTime;

    type = 2;

    time_a = call LocalTime.get();

    call ECDSA.init(&CAPublicKey); 

    time_b = call LocalTime.get();

    t = time_b - time_a;

    pTime = (time_msg *)report.data;
    pTime->type = 2;
    pTime->t = t;
    pTime->pass = 0;
    call TimeMsg.send(1, &report, sizeof(time_msg));
     
  }

  void sign(){
    uint32_t time_a, time_b;
    packet_msg *pPacket;

    type = 3;

    time_a = call LocalTime.get();

    call ECDSA.sign((uint8_t*)&ClientPublicKey, sizeof(Point), r, s, CAPrivateKey);;

    time_b = call LocalTime.get();

    t = time_b - time_a;

    pPacket = (packet_msg *)report.data;
    pPacket->c_len = sizeof(Point);
    memcpy(pPacket->content, &ClientPublicKey, sizeof(Point));
    pPacket->r_len = KEYDIGITS*NN_DIGIT_LEN;
    call NN.Encode(pPacket->r, KEYDIGITS*NN_DIGIT_LEN, r, KEYDIGITS);
    call NN.Encode(pPacket->s, KEYDIGITS*NN_DIGIT_LEN, s, KEYDIGITS);
    call PacketMsg.send(1, &report, sizeof(packet_msg));
  }

  void verify(){
    uint32_t time_a, time_b;
    time_msg *pTime;

    type = 4;

    time_a = call LocalTime.get();

    pass = call ECDSA.verify((uint8_t *)&ClientPublicKey, sizeof(Point), r, s, &CAPublicKey);   

    time_b = call LocalTime.get();

    t = time_b - time_a;

    pTime = (time_msg *)report.data;
    pTime->type = 4;
    pTime->t = t;
    pTime->pass = pass;
    call TimeMsg.send(1, &report, sizeof(time_msg));
    if(pass == 1)
      call Leds.led0Toggle();
  }

  event void Boot.booted(){
    call SerialControl.start();
  }
  
  event void SerialControl.startDone(error_t e) {
    call myTimer.startOneShot(5000);
  }
  
  event void SerialControl.stopDone(error_t e) {
  }

  event void myTimer.fired(){
    round_index = 1;
    init_data();
  }

  event void PubKeyMsg.sendDone(message_t* sent, error_t error) {
    time_msg *pTime;

    type = 1;
    pTime = (time_msg *)report.data;
    pTime->type = 1;
    pTime->t = t;
    pTime->pass = 0;
    call TimeMsg.send(1, &report, sizeof(time_msg));
  }

  event void PriKeyMsg.sendDone(message_t* sent, error_t success) {
    ecc_init();
  }

  event void PacketMsg.sendDone(message_t* sent, error_t success) {
    time_msg *pTime;

    type = 3;
    pTime = (time_msg *)report.data;
    pTime->type = 3;
    pTime->t = t;
    pTime->pass = 0;
    call TimeMsg.send(1, &report, sizeof(time_msg));
  }

  event void TimeMsg.sendDone(message_t* sent, error_t success) {

    if (type == 0){
      //trace(DBG_USR1, "before gen_publicKey\n");
      gen_PublicKey(); 
    }else if (type == 1){
      //trace(DBG_USR1, "before ecdsa_init\n");
      ecdsa_init();
    }else if (type == 2){
      //trace(DBG_USR1, "before sign\n");
      sign();
    }else if (type == 3){
      //trace(DBG_USR1, "before verify\n");
      verify();
    }else if (type == 4){
      if(round_index < MAX_ROUNDS){
  init_data();
  round_index++;
      }
    }
  }

}

