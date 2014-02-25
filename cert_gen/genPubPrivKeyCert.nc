includes result;
includes ECC;
includes sha1;

configuration genPubPrivKeyCert{
}

implementation {
  components MainC, genPubPrivKeyCertM, LedsC, RandomLfsrC, NNM, ECCC, ECDSAC;
  //components SerialStartC;
  //components PrintfC;
  MainC.SoftwareInit -> RandomLfsrC.Init;
  genPubPrivKeyCertM.Boot -> MainC.Boot;

  components new TimerMilliC(), LocalTimeMilliC;

  genPubPrivKeyCertM.myTimer -> TimerMilliC;
  genPubPrivKeyCertM.LocalTime -> LocalTimeMilliC;
  genPubPrivKeyCertM.Random -> RandomLfsrC;
  genPubPrivKeyCertM.Leds -> LedsC;

  components SerialActiveMessageC as Serial;

  genPubPrivKeyCertM.PubKeyMsg -> Serial.AMSend[AM_PUBLIC_KEY_MSG];
  genPubPrivKeyCertM.PriKeyMsg -> Serial.AMSend[AM_PRIVATE_KEY_MSG];
  genPubPrivKeyCertM.PacketMsg -> Serial.AMSend[AM_PACKET_MSG];
  genPubPrivKeyCertM.TimeMsg -> Serial.AMSend[AM_TIME_MSG];
  genPubPrivKeyCertM.SerialControl -> Serial;

  genPubPrivKeyCertM.NN -> NNM.NN;
  genPubPrivKeyCertM.ECC -> ECCC.ECC;
  genPubPrivKeyCertM.ECDSA -> ECDSAC;



}

