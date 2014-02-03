configuration OCBModeC {
	provides interface OCBMode;
}
implementation {
    components OCBModeP, SkipJackM;
    OCBMode = OCBModeP;
    OCBModeP.cipher -> SkipJackM;

}