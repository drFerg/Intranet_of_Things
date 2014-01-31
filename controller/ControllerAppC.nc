#include "AMKNoT.h"
configuration ControllerAppC { }
implementation
{
    components ControllerC, MainC, SerialStartC, SerialActiveMessageC;
    components KNoTC, ChannelTableC, ChannelStateC, LEDBlinkC;
/* Debug */
    #if DEBUG
    components PrintfC;
    #endif

/* Timers */
    components new TimerMilliC();
    components new SerialAMSenderC(AM_KNOT_MESSAGE);
    components new SerialAMReceiverC(AM_KNOT_MESSAGE);

    ControllerC.Boot -> MainC;
    ControllerC.SerialControl -> SerialActiveMessageC;

    ControllerC.SerialSend -> SerialAMSenderC;
    ControllerC.SerialReceive ->SerialAMReceiverC;
    ControllerC.ChannelTable -> ChannelTableC;
    ControllerC.ChannelState -> ChannelStateC;
    ControllerC.Timer -> TimerMilliC;
    ControllerC.LEDBlink -> LEDBlinkC;
    ControllerC.KNoT -> KNoTC;

}
