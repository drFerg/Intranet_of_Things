#include "AMKNoT.h"
configuration KNoTC {
	provides interface KNoT;
}

implementation {
	components MainC;
	components ActiveMessageC;
	components LEDBlinkC;
	components KNoTP;
    components new AMSenderC(AM_KNOT_MESSAGE);
    components new SerialAMSenderC(AM_KNOT_MESSAGE);
    components new AMReceiverC(AM_KNOT_MESSAGE);
    KNoT = KNoTP;
    KNoTP.Boot -> MainC;
    KNoTP.RadioControl -> ActiveMessageC;
    KNoTP.AMSend -> AMSenderC;
    KNoTP.AMPacket ->AMSenderC;
    KNoTP.Receive -> AMReceiverC;
    //KNoTP.Packet ->AMSenderC;
    KNoTP.SerialAMSend -> SerialAMSenderC;
    KNoTP.LEDBlink -> LEDBlinkC;
}