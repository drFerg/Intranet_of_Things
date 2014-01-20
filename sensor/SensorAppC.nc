#include "AMKNoT.h"
configuration SensorAppC { }
implementation
{
    components SensorC, MainC, ActiveMessageC, SerialStartC, SerialActiveMessageC;
    components KNoTC, ChannelTableC, ChannelStateC, LEDBlinkC;
/* Debug */
    #if DEBUG
    components PrintfC;
    #endif

/* Timers */
    components new TimerMilliC();

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

    SensorC.Boot -> MainC;
    SensorC.RadioControl -> ActiveMessageC;
    SensorC.AMSend -> AMSenderC;
    SensorC.Receive -> AMReceiverC;
    SensorC.ChannelTable -> ChannelTableC;
    SensorC.ChannelState -> ChannelStateC;
    SensorC.Timer -> TimerMilliC;
    SensorC.LightSensor -> LightSensor;
    #if TELOS
    SensorC.TempSensor -> TempSensor.Temperature;
    #else 
    SensorC.TempSensor -> TempSensor;
    #endif
    SensorC.LEDBlink -> LEDBlinkC;
    SensorC.KNoT -> KNoTC;

}
