module LEDBlinkP @safe() {
	provides interface LEDBlink;
	uses interface Timer<TMilli> as LEDTimer0;
    uses interface Timer<TMilli> as LEDTimer1;
    uses interface Timer<TMilli> as LEDTimer2;
    uses interface Leds;
}
implementation {

		/*-----------LED Commands------------------------------- */
    void pulse_green_led(int t){
        call Leds.led1Toggle();
        call LEDTimer2.startOneShot(t);
    }

    void pulse_red_led(int t){
        call Leds.led0Toggle();
        call LEDTimer0.startOneShot(t);
    }

    void pulse_blue_led(int t){
        call Leds.led2Toggle();
        call LEDTimer1.startOneShot(t);
    }

    	/*-----------Reports------------------------------- */
  	// Use LEDs to report various status issues.
    command void LEDBlink.report_problem() {pulse_red_led(1000);pulse_blue_led(1000);pulse_green_led(1000); }
    command void LEDBlink.report_sent() {pulse_green_led(100);}
    command void LEDBlink.report_received() {pulse_red_led(1000);}
    command void LEDBlink.report_dropped(){pulse_red_led(100);pulse_blue_led(100);}


    /*-----------LED Timer EVENTS------------------------------- */
    event void LEDTimer1.fired(){
        call Leds.led2Toggle();
    }

    event void LEDTimer0.fired(){
        call Leds.led0Toggle();
    }
    event void LEDTimer2.fired(){
        call Leds.led1Toggle();
    }
}
