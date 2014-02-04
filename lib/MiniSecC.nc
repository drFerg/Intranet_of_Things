configuration MiniSecC {
	provides interface MiniSec;
}

implementation {
	components OCBModeC;
    components MiniSecP;

    MiniSec = MiniSecP;
    MiniSecP.CipherMode -> OCBModeC;


}