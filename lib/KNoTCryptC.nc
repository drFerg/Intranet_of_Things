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
    components NNM, ECCC, ECDSAC;

    components new AMSenderC(AM_KNOT_MESSAGE);
    components new AMReceiverC(AM_KNOT_MESSAGE);

    KNoTCrypt = KNoTCryptP;
    KNoTCryptP.Boot -> MainC;
    KNoTCryptP.RadioControl -> ActiveMessageC;
    KNoTCryptP.AMSend -> AMSenderC;
    KNoTCryptP.AMPacket ->AMSenderC;
    KNoTCryptP.Receive -> AMReceiverC;
    KNoTCryptP.LEDBlink -> LEDBlinkC;
    KNoTCryptP.MiniSec -> MiniSecC;
    KNoTCryptP.NN -> NNM.NN;
    KNoTCryptP.ECC -> ECCC.ECC;
    KNoTCryptP.ECDSA -> ECDSAC;
}