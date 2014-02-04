#include "AMKNoT.h"
configuration KNoTCryptC {
	provides interface KNoTCrypt;
}

implementation {
	components MainC;
	components ActiveMessageC;
	components LEDBlinkC;
	components KNoTCryptP;
    components MiniSecC;

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
}