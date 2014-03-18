includes AMKNoT;
configuration SensorAppC { }
implementation
{
    components SensorC, MainC, SerialStartC, SerialActiveMessageC;
    components KNoTCryptC, ChannelTableC, ChannelStateC, LEDBlinkC;
/* Debug */
    #if DEBUG
    components PrintfC;
    #endif

/* Timers */
    components new TimerMilliC(), 
    new TimerMilliC() as Cleaner;

/* Sensors */
    #if TELOS
    //components new HamamatsuS10871TsrC() as LightSensor,
    components new SensirionSht11C() as TempSensor;
    #else
    components new DemoSensorC() as LightSensor,
    new DemoSensorC() as TempSensor;
    #endif
  

    SensorC.Boot -> MainC;
    SensorC.ChannelTable -> ChannelTableC;
    SensorC.ChannelState -> ChannelStateC;
    SensorC.Timer -> TimerMilliC;
    SensorC.CleanerTimer -> Cleaner;
    //SensorC.LightSensor -> LightSensor;
    #if TELOS
    SensorC.TempSensor -> TempSensor.Temperature;
    #else 
    SensorC.TempSensor -> TempSensor;
    #endif
    SensorC.LEDBlink -> LEDBlinkC;
    SensorC.KNoT -> KNoTCryptC;

}
