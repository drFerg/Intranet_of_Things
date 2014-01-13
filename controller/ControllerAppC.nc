#include "AMKNoT.h"
configuration ControllerAppC { }
implementation
{
    components ControllerC, MainC, ActiveMessageC, LedsC, SerialStartC,
    ChannelTableC, ChannelStateC, SerialActiveMessageC;
    components KNoTC;
/* Debug */
    #if DEBUG
    components PrintfC;
    #endif

/* Timers */
    components new TimerMilliC(), 
    new TimerMilliC() as LEDTimer0,
    new TimerMilliC() as LEDTimer1,
    new TimerMilliC() as LEDTimer2;

/* Sensors */
    #if TELOS
    components new HamamatsuS10871TsrC() as LightSensor,
    new SensirionSht11C() as TempSensor;
    #else
    components new DemoSensorC() as LightSensor,
    new DemoSensorC() as TempSensor;
    #endif

/* Radio/Serial*/
    components new AMSenderC(AM_KNOT_MESSAGE);
    components new AMReceiverC(AM_KNOT_MESSAGE);
    components new SerialAMSenderC(AM_KNOT_MESSAGE);
    components new SerialAMReceiverC(AM_KNOT_MESSAGE);

    ControllerC.Boot -> MainC;
    ControllerC.RadioControl -> ActiveMessageC;
    ControllerC.AMSend -> AMSenderC;
    ControllerC.Receive -> AMReceiverC;
    ControllerC.SerialAMSend -> SerialAMSenderC;
    ControllerC.SerialReceive -> SerialAMReceiverC;
    ControllerC.ChannelTable -> ChannelTableC;
    ControllerC.ChannelState -> ChannelStateC;
    ControllerC.Timer -> TimerMilliC;
    ControllerC.LEDTimer0 -> LEDTimer0;
    ControllerC.LEDTimer1 -> LEDTimer1;
    ControllerC.LEDTimer2 -> LEDTimer2;
    ControllerC.LightSensor -> LightSensor;
    #if TELOS
    ControllerC.TempSensor -> TempSensor.Temperature;
    #else 
    ControllerC.TempSensor -> TempSensor;
    #endif
    ControllerC.Leds -> LedsC;
    ControllerC.KNoT -> KNoTC;

}
