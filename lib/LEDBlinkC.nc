
configuration LEDBlinkC {
	provides interface LEDBlink;
}

implementation {
    components new TimerMilliC() as LEDTimer0,
               new TimerMilliC() as LEDTimer1,
               new TimerMilliC() as LEDTimer2;
	components LedsC, LEDBlinkP;
    LEDBlink = LEDBlinkP;
    LEDBlinkP.LEDTimer0 -> LEDTimer0;
    LEDBlinkP.LEDTimer1 -> LEDTimer1;
    LEDBlinkP.LEDTimer2 -> LEDTimer2;
    LEDBlinkP.Leds -> LedsC;
}