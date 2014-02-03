#ifndef HEADER_SKIPJACK_LOCL_H
#define HEADER_SKIPJACK_LOCL_H

/* NOTE: CTR mode is big-endian.  The rest of the Skipjack code
 * is endian-neutral. */
/*#ifdef __IAR_SYSTEMS_ICC__
    #define L_ENDIAN
#endif */

typedef unsigned long u32;
typedef unsigned short u16;
typedef unsigned char u8;

#define SKIPJACK_ENCRYPT	1
#define SKIPJACK_DECRYPT	0
#define SKIPJACK_BLOCK_SIZE 8

/*#ifdef  __cplusplus
extern "C" {
#endif*/

struct skipjack_key_st {
#ifdef OPTIMISE_SIZE
	#warning "Using ekey size 12"		
    unsigned char ekey[12]; // 10 bytes + 2 bytes (see Skipjack_encrypt)
#elif defined(TINYSEC)
    #warning "Using ekey size 128"
	unsigned char ekey[128];// 4 bytes * 32 rounds
#else
	#warning "Using ekey size 38"
	unsigned char ekey[38];	// 4 bytes * 8 rounds + 6 bytes (see 
							// Skipjack_encrypt)
#endif
	//int rounds; //hard-coded 32 rounds	
};
typedef struct skipjack_key_st SKIPJACK_KEY;




#endif
