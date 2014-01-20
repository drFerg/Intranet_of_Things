#include "AMKNoT.h"
configuration ControllerAppC { }
implementation
{
    components ControllerC, MainC, ActiveMessageC, SerialStartC, SerialActiveMessageC;
    components KNoTC, ChannelTableC, ChannelStateC, LEDBlinkC;
/* Debug */
    #if DEBUG
    components PrintfC;
    #endif

/* Timers */
    components new TimerMilliC();

/* Radio/Serial*/
    components new AMSenderC(AM_KNOT_MESSAGE);
    components new AMReceiverC(AM_KNOT_MESSAGE);
    components new SerialAMSenderC(AM_KNOT_MESSAGE);
    components new SerialAMReceiverC(AM_KNOT_MESSAGE);

    ControllerC.Boot -> MainC;
    ControllerC.RadioControl -> ActiveMessageC;
    ControllerC.SerialControl -> SerialActiveMessageC;
    ControllerC.AMSend -> AMSenderC;
    ControllerC.Receive -> AMReceiverC;
    ControllerC.SerialSend -> SerialAMSenderC;
    ControllerC.SerialReceive ->SerialAMReceiverC;
    ControllerC.ChannelTable -> ChannelTableC;
    ControllerC.ChannelState -> ChannelStateC;
    ControllerC.Timer -> TimerMilliC;
    ControllerC.LEDBlink -> LEDBlinkC;
    ControllerC.KNoT -> KNoTC;

}
