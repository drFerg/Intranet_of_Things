#include "AMKNoT.h"
includes ECC;
includes ECIES;
configuration KNoTCryptC {
	provides interface KNoTCrypt;
}

implementation {
	components MainC;
	components ActiveMessageC;
	components LEDBlinkC;
	components KNoTCryptP;
    components MiniSecC;
    /*ECC encryption components */
    components NNM, ECCC, ECDSAC, ECIESC;
    components RandomLfsrC;
    components LocalTimeMilliC;

    components new AMSenderC(AM_KNOT_MESSAGE);
    components new AMReceiverC(AM_KNOT_MESSAGE);
    MainC.SoftwareInit -> RandomLfsrC.Init;
    KNoTCrypt = KNoTCryptP;
    KNoTCryptP.Boot -> MainC.Boot;
    KNoTCryptP.Random -> RandomLfsrC;
    KNoTCryptP.RadioControl -> ActiveMessageC;
    KNoTCryptP.AMSend -> AMSenderC;
    KNoTCryptP.AMPacket -> AMSenderC;
    KNoTCryptP.Receive -> AMReceiverC;
    KNoTCryptP.LEDBlink -> LEDBlinkC;
    KNoTCryptP.MiniSec -> MiniSecC;
    KNoTCryptP.NN -> NNM.NN;
    KNoTCryptP.ECC -> ECCC.ECC;
    KNoTCryptP.ECDSA -> ECDSAC; /* Sign/Verify */
    KNoTCryptP.ECIES -> ECIESC; /* Encrypt/Decrypt */
    KNoTCryptP.LocalTime -> LocalTimeMilliC;
}