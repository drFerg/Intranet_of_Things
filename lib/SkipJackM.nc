/* Implementation of Skipjack, adapted from TinySec:
 *
 * "Copyright (c) 2000-2002 The Regents of the University  of California.  
 * All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 * 
 * IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE UNIVERSITY OF
 * CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 *
 * Authors: Naveen Sastry, Yee Wei Law
 * Date:    12/28/02
 * 
 * Ported From C to NesC by Evan Gaustad 12/1/2005
 * 
 * Note:
 * - Comparison between TinySec's and my version:
 *
 *   TinySec	No optimisation	Max speed optimisation
 *   Key setup	26113			25592
 *   Encryption	2969			1597
 *
 *   My			No optimisation	Max speed optimisation
 *   Key setup	187				187
 *   Encryption	2988			1583
 *   
 *   Instructions in overhead	Cycles
 *   mov.w	0x14(SP), R14		3
 *   mov.w	#0x2, R5			2
 *   add.w	R14,R5				1
 *   mov.w	R5,R13				1
 * 
 */

includes SkipJack;


// G-permutation: 4-round Feistal structure
#define G(key, b, bLeft, bRight)		\
     ( bLeft   = (b >> 8),				\
       bRight  = b,						\
       bLeft  ^= F[bRight ^ (key)[0]],	\
       bRight ^= F[bLeft  ^ (key)[1]],	\
       bLeft  ^= F[bRight ^ (key)[2]],	\
       bRight ^= F[bLeft  ^ (key)[3]],	\
       (bLeft << 8) | bRight)

#define G_INV(key, b, bLeft, bRight)	\
     ( bLeft   = (b >> 8),				\
       bRight  = b,						\
       bRight ^= F[bLeft  ^ (key)[3]],	\
       bLeft  ^= F[bRight ^ (key)[2]],	\
       bRight ^= F[bLeft  ^ (key)[1]],	\
       bLeft  ^= F[bRight ^ (key)[0]],	\
       (bLeft << 8) | bRight)

// Rule A:
#define RULE_A(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight ) { \
    tmp = w4;                                \
    w4 = w3;                                 \
    w3 = w2;                                 \
    w2 = G(skey, w1, bLeft, bRight);         \
    w1 = w2 ^ tmp ^ counter;                 \
    counter++; }

#define RULE_A_INV(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight) { \
    tmp = w4;                                \
    w4 = w1 ^ w2 ^ counter;                  \
    w1 = G_INV(skey, w2, bLeft, bRight);     \
    w2 = w3;                                 \
    w3 = tmp;                                \
    counter--; }

// Rule B: 
#define RULE_B(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight ) { \
    tmp = w1;                                \
    w1 = w4;                                 \
    w4 = w3;                                 \
    w3 = tmp ^ w2 ^ counter;                 \
    w2 = G(skey, tmp, bLeft, bRight);        \
    counter++; }

#define RULE_B_INV(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight ) { \
    tmp = w1;                                \
    w1 = G_INV(skey, w2, bLeft, bRight);     \
    w2 = w1 ^ w3 ^ counter;                  \
    w3 = w4;                                 \
    w4 = tmp;                                \
    counter--; }

#ifdef L_ENDIAN
#   define SKIPJACK_CTR64_INC(counter)\
    	c = ((u32)(counter)[4] << 24) ^ \
            ((u32)(counter)[5] << 16) ^ \
	        ((u32)(counter)[6] << 8) ^ \
            (u32)(counter)[7];\
    	c++;\
	    (counter)[4] = (u8)(c >> 24); \
        (counter)[5] = (u8)(c >> 16); \
    	(counter)[6] = (u8)(c >> 8); \
        (counter)[7] = (u8)c; 
#else
#   define SKIPJACK_CTR64_INC(counter)\
    	c = ((u32)(counter)[0] << 24) ^ \
            ((u32)(counter)[1] << 16) ^ \
	        ((u32)(counter)[2] << 8) ^ \
            (u32)(counter)[3];\
    	c++;\
    	(counter)[0] = (u8)(c >> 24); \
        (counter)[1] = (u8)(c >> 16); \
    	(counter)[2] = (u8)(c >> 8); \
        (counter)[3] = (u8)c; 
#endif

module SkipJackM {
  provides interface BlockCipher;
  //provides interface BlockCipherInfo;
}
implementation
{
    //void dumpBuffer (char * bufName, uint8_t * buf, uint8_t size);
	  
	const uint8_t F[256] = 
	{
	   0xA3, 0xD7, 0x09, 0x83, 0xF8, 0x48, 0xF6, 0xF4,
	   0xB3, 0x21, 0x15, 0x78, 0x99, 0xB1, 0xAF, 0xF9,
	   0xE7, 0x2D, 0x4D, 0x8A, 0xCE, 0x4C, 0xCA, 0x2E,
	   0x52, 0x95, 0xD9, 0x1E, 0x4E, 0x38, 0x44, 0x28,
	   0x0A, 0xDF, 0x02, 0xA0, 0x17, 0xF1, 0x60, 0x68,
	   0x12, 0xB7, 0x7A, 0xC3, 0xE9, 0xFA, 0x3D, 0x53,
	   0x96, 0x84, 0x6B, 0xBA, 0xF2, 0x63, 0x9A, 0x19,
	   0x7C, 0xAE, 0xE5, 0xF5, 0xF7, 0x16, 0x6A, 0xA2,
	   0x39, 0xB6, 0x7B, 0x0F, 0xC1, 0x93, 0x81, 0x1B,
	   0xEE, 0xB4, 0x1A, 0xEA, 0xD0, 0x91, 0x2F, 0xB8,
	   0x55, 0xB9, 0xDA, 0x85, 0x3F, 0x41, 0xBF, 0xE0,
	   0x5A, 0x58, 0x80, 0x5F, 0x66, 0x0B, 0xD8, 0x90,
	   0x35, 0xD5, 0xC0, 0xA7, 0x33, 0x06, 0x65, 0x69,
	   0x45, 0x00, 0x94, 0x56, 0x6D, 0x98, 0x9B, 0x76,
	   0x97, 0xFC, 0xB2, 0xC2, 0xB0, 0xFE, 0xDB, 0x20,
	   0xE1, 0xEB, 0xD6, 0xE4, 0xDD, 0x47, 0x4A, 0x1D,
	   0x42, 0xED, 0x9E, 0x6E, 0x49, 0x3C, 0xCD, 0x43,
	   0x27, 0xD2, 0x07, 0xD4, 0xDE, 0xC7, 0x67, 0x18,
	   0x89, 0xCB, 0x30, 0x1F, 0x8D, 0xC6, 0x8F, 0xAA,
	   0xC8, 0x74, 0xDC, 0xC9, 0x5D, 0x5C, 0x31, 0xA4,
	   0x70, 0x88, 0x61, 0x2C, 0x9F, 0x0D, 0x2B, 0x87,
	   0x50, 0x82, 0x54, 0x64, 0x26, 0x7D, 0x03, 0x40,
	   0x34, 0x4B, 0x1C, 0x73, 0xD1, 0xC4, 0xFD, 0x3B,
	   0xCC, 0xFB, 0x7F, 0xAB, 0xE6, 0x3E, 0x5B, 0xA5,
	   0xAD, 0x04, 0x23, 0x9C, 0x14, 0x51, 0x22, 0xF0,
	   0x29, 0x79, 0x71, 0x7E, 0xFF, 0x8C, 0x0E, 0xE2,
	   0x0C, 0xEF, 0xBC, 0x72, 0x75, 0x6F, 0x37, 0xA1,
	   0xEC, 0xD3, 0x8E, 0x62, 0x8B, 0x86, 0x10, 0xE8,
	   0x08, 0x77, 0x11, 0xBE, 0x92, 0x4F, 0x24, 0xC5,
	   0x32, 0x36, 0x9D, 0xCF, 0xF3, 0xA6, 0xBB, 0xAC,
	   0x5E, 0x6C, 0xA9, 0x13, 0x57, 0x25, 0xB5, 0xE3,
	   0xBD, 0xA8, 0x3A, 0x01, 0x05, 0x59, 0x2A, 0x46
	};
	
    /**
     *  command init - used to initialize the key, which is expanded and the
     *                 resulting key is stored in *context.
     *  parameters:
     *     *context - is a CipherContext containing the appropriate space for
     *                the encryption key:
     *                   OPTIMISE_SIZE 12 bytes
     *                   TINYSEC 10 bytes
     *                   SPEED_OPTIMIZE 38 bytes
     *     blockSize - size of input/output (bytes)
     *     keySize - key length (bytes)
     *     *key - pointer to key.
     *  output:
     *     *context will contain the expanded key and will be ready for use with
     *     the block cipher.
     */	
	command error_t BlockCipher.init(CipherContext * context, uint8_t 
                                      blockSize, uint8_t keySize, uint8_t * key)
    {
		SKIPJACK_KEY *skey = (SKIPJACK_KEY *)context;
		unsigned char *userKey = (unsigned char *)key;
		register int i;
		// SkipJack only supports keySize of 10 bytes and blockSize of 8 bytes
    	if(blockSize != 8 || keySize != 10 || context == NULL || key == NULL) {
    	    return FAIL;
    	}
		
    	// Expand Key
		#ifdef OPTIMISE_SIZE
			for (i = 0; i < 10; i++) {
				skey->ekey[i] = userKey[i];
			}
			skey->ekey[10] = userKey[0];
			skey->ekey[11] = userKey[1];
		#elif defined(TINYSEC)
			for (i = 0; i < 128; i++) {
				skey->ekey[i] = userKey[i % 10];
		    }
		#else
			for (i = 0; i < 38; i++) {
				skey->ekey[i] = userKey[i % 10];
		    }
		#endif
    	return SUCCESS;	
    }	
    
    /**
     *  command encrypt - used to encrypt one block of plaintext and store
     *                    the resulting encrypted value in cipherBlock.
     *                    the init command must have been called prior to
     *                    execution of this function.
     *  parameters:
     *     *context - is a CipherContext containing the initialized key
     *     *plainBlock - block of plaintext to encrypt
     *     *cipherBlock - pointer to memory of blockSize bytes where the result
     *                    will be stored
     *
     *  output:
     *     *cipherBlock will contain the encrypted form of the plainBlock.
     */	
	async command error_t BlockCipher.encrypt(CipherContext *context,
					     					   uint8_t * plainBlock,
					     					   uint8_t * cipherBlock)
	{ 
		SKIPJACK_KEY *key = (SKIPJACK_KEY *)context;
		uint8_t *in = plainBlock;
		uint8_t *out = cipherBlock;

		register u8 counter = 1;	
	#ifdef OPTIMISE_SIZE	
		register signed char idx = 0;
	#else
		register const u8 *skey = (u8 *)key->ekey;
	#endif	
		register u16 w1, w2, w3, w4, tmp;
		register u8 bLeft, bRight;
		
		w1 = (u16)in[0]<<8 ^ (u16)in[1];
		w2 = (u16)in[2]<<8 ^ (u16)in[3];
		w3 = (u16)in[4]<<8 ^ (u16)in[5];
		w4 = (u16)in[6]<<8 ^ (u16)in[7];
		
	#ifdef OPTIMISE_SIZE
		// counter	key indices
		// 1		0,1,2,3
		// 2		4,5,6,7
		// 3		8,9,0,1 <-- this is why we need 10+2 bytes in the expanded key
		// 4		2,3,4,5
		// 5		6,7,8,9
		// ----------------
		// 6		0,1,2,3
		// ...
		while (counter <= 32) {
			if (counter <= 8 || (counter >= 17 && counter <= 24)) {
				RULE_A((key->ekey+idx), w1, w2, w3, w4, counter, tmp, bLeft, bRight );
			} else {
				RULE_B((key->ekey+idx), w1, w2, w3, w4, counter, tmp, bLeft, bRight );
			}
			idx += 4;
			if (idx >= 10)
				idx -= 10;
		}
	#else
		while (counter <= 8) {
			RULE_A(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight );
			skey += 4;
		}
	#ifndef TINYSEC
		skey = key->ekey+2;
	#endif	
		while (counter <= 16) {
			RULE_B(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight );
			skey += 4;
		}
	#ifndef TINYSEC	
		skey = key->ekey+4;
	#endif
		while (counter <= 24) {
			RULE_A(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight );
			skey += 4;
		}
	#ifndef TINYSEC	
		skey = key->ekey+6;
	#endif
		while (counter <= 32) {
			RULE_B(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight );
			skey += 4;
		}
	#endif
	
		out[0] = (u8)(w1 >> 8); out[1] = (u8)w1;
		out[2] = (u8)(w2 >> 8); out[3] = (u8)w2;
		out[4] = (u8)(w3 >> 8); out[5] = (u8)w3;
		out[6] = (u8)(w4 >> 8); out[7] = (u8)w4;
		
		return SUCCESS;	
	}
	
	
	
    /**
     *  command decrypt - used to decrypt one block of ciphertext and store
     *                    the resulting plaintext in *plainBlock.  The init
     *                    command must have been called prior to execution of 
     *                    this function.
     *  parameters:
     *     *context - is a CipherContext containing the key
     *     *plainBlock - pointer to memory of blockSize bytes where the 
     *                   resulting decrypted value will be stored.
     *     *cipherBlock - block of ciphertext to decrypt
     *
     *  output:
     *     *plainBlock will contain the decrypted form of the cipherBlock.
     */	
	async command error_t BlockCipher.decrypt(CipherContext * context,
					     uint8_t * cipherBlock,
					     uint8_t * plainBlock)
    {
    	
    	SKIPJACK_KEY *key = (SKIPJACK_KEY *)context;
		uint8_t *in = cipherBlock;
		uint8_t *out = plainBlock;
    	
    	register u8 counter = 32;	
	#ifdef OPTIMISE_SIZE	
		register signed char idx;
	#else	
		register const u8 *skey;
	#endif	
		register u16 w1, w2, w3, w4, tmp;
		register u8 bLeft, bRight;
		
		w1 = (u16)in[0]<<8 ^ (u16)in[1];
		w2 = (u16)in[2]<<8 ^ (u16)in[3];
		w3 = (u16)in[4]<<8 ^ (u16)in[5];
		w4 = (u16)in[6]<<8 ^ (u16)in[7];
		
	#ifdef OPTIMISE_SIZE
		// counter	key indices
		// 32		4,5,6,7
		// 31		0,1,2,3
		// 30		6,7,8,9
		// 29		2,3,4,5
		// 28		8,9,0,1
		// ----------------
		// 27		4,5,6,7
		// ...
		idx = 4;
		while (counter >= 1) {
			if (counter >= 25 || (counter >= 9 && counter <= 16)) {
				RULE_B_INV((key->ekey+idx), w1, w2, w3, w4, counter, tmp, bLeft, bRight );			
			} else {
				RULE_A_INV((key->ekey+idx), w1, w2, w3, w4, counter, tmp, bLeft, bRight );
			}
			idx -= 4;
			if (idx < 0)
				idx += 10;
		}	
	#else
	#ifdef TINYSEC	
		skey = key->ekey+124;
	#else	
		skey = key->ekey+34;
	#endif	
		while (counter >= 25) {
			RULE_B_INV(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight );
			skey -= 4;
		}
	#ifndef TINYSEC	
		skey = key->ekey+32;
	#endif
		while (counter >= 17) {
			RULE_A_INV(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight );
			skey -= 4;
		}
	#ifndef TINYSEC	
		skey = key->ekey+30;
	#endif	
		while (counter >= 9) {
			RULE_B_INV(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight );
			skey -= 4;
		}
	#ifndef TINYSEC	
		skey = key->ekey+28;
	#endif
		while (counter >= 1) {
			RULE_A_INV(skey, w1, w2, w3, w4, counter, tmp, bLeft, bRight );
			skey -= 4;
		}
	#endif
		
		out[0] = (u8)(w1 >> 8); out[1] = (u8)w1;
		out[2] = (u8)(w2 >> 8); out[3] = (u8)w2;
		out[4] = (u8)(w3 >> 8); out[5] = (u8)w3;
		out[6] = (u8)(w4 >> 8); out[7] = (u8)w4;

    	return SUCCESS;	
    }
    
  /**
  * Debug function
  *
  void dumpBuffer (char * bufName, uint8_t * buf, uint8_t size)
    {
      uint8_t i = 0;
      // fixme watch buffer overrun
      char tmp[512];
      for (; i < size; i++) {
       // sprintf (tmp + i * 3, "%2x ", (char)buf[i] & 0xff);

      }
      dbg(DBG_USR1, "%s: {%s}\n", bufName, tmp);
    }
  */
}


