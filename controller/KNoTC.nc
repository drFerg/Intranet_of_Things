#include "AMKNoT.h"
configuration KNoTC {
	provides interface KNoT;
}

implementation {
	components MainC;
	components ActiveMessageC;
	components LedsC;
	components KNoTP;
    components new AMSenderC(AM_KNOT_MESSAGE);
    KNoT = KNoTP;
    KNoTP.Boot -> MainC;
    KNoTP.RadioControl -> ActiveMessageC;
    KNoTP.AMSend -> AMSenderC;
}