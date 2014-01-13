#include "AMKNoT.h"
configuration ControllerAppC { }
implementation
{
    components ControllerC, MainC, ActiveMessageC, SerialActiveMessageC, LedsC, SerialStartC,
        ChannelTableC, ChannelStateC; 
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
    //components new SerialAMSenderC(AM_KNOT_MESSAGE);
    //components new SerialAMReceiverC(AM_KNOT_MESSAGE);


    ControllerC.Boot -> MainC;
    ControllerC.RadioControl -> ActiveMessageC;
    ControllerC.RadioAMSend -> AMSenderC;
    ControllerC.RadioReceive -> AMReceiverC;
    //ControllerC.SerialAMSend -> SerialAMSenderC;
    //ControllerC.SerialReceive -> SerialAMReceiverC;
    ControllerC.ChannelTable -> ChannelTableC;
    ControllerC.ChannelState -> ChannelState;
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

}
