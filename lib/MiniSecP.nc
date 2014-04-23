#if DEBUG
#include "printf.h"
#define PRINTF(...) printf(__VA_ARGS__)
#define PRINTFFLUSH(...) printfflush()
#elif SIM
#define PRINTF(...) dbg("DEBUG",__VA_ARGS__)
#define PRINTFFLUSH(...)
#else  
#define PRINTF(...)
#define PRINTFFLUSH(...)
#endif

#ifndef TAG_LEN
#define TAG_LEN 4
#endif /* TAG_LEN */

/* Lower N Bits */
#define LNB_MASK(N) (0xff >> (8 - N))
#define IV_BITS 6 /* Lower 6 bits of IV being TX'd */

module MiniSecP @safe() {
  provides interface MiniSec as Sec;
  uses interface OCBMode as CipherMode;
}
implementation {

  error_t incrementIV(uint8_t *iv_block);
  
#ifdef DEBUG
#define TEST_LEN 16
  void test(CipherModeContext *cc){
    uint8_t testTag[] = {0x00,0x00,0x00,0x00};
    uint8_t plainMsg[] = {0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08, 
                          0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0x10,
                        };
    uint8_t decryptedMsg[TEST_LEN];
    uint8_t cipherMsg[TEST_LEN];
    uint8_t valid = 0;
    memset(&decryptedMsg, 0, TEST_LEN);
    memset(&cipherMsg, 0, TEST_LEN);

    call CipherMode.encrypt(cc, plainMsg, cipherMsg, TEST_LEN, testTag);
    call CipherMode.decrypt(cc, cipherMsg, decryptedMsg, TEST_LEN, testTag, &valid);
    PRINTF("INIT SUCCESSFUL: %s\n", (valid?"YES":"NO"));PRINTFFLUSH();
  }
#endif /* DEBUG */

  command error_t Sec.init(CipherModeContext *cc, uint8_t *key, uint8_t key_size,
                            uint8_t num_precomp_blks) {    
    call CipherMode.init(cc, key_size, key, TAG_LEN, num_precomp_blks); 
    memset(&(cc->iv), 0, BLOCK_SIZE);
#ifdef DEBUG
    test(cc);
#endif /* DEBUG */
    return SUCCESS;
  }

  command error_t Sec.encrypt(CipherModeContext *cc, uint8_t *plain_blocks, uint8_t length, 
                              uint8_t *cipher_blocks, uint8_t *tag) {
    PRINTF("len: %d\n", length);
    PRINTF("IV was = %d\n", cc->iv[7]);
    if(incrementIV(cc->iv)) {PRINTF("OH NOES\n");return FAIL;}
    PRINTF("IV now = %d\n", cc->iv[7]);
    call CipherMode.encrypt(cc, plain_blocks, cipher_blocks, length, tag);
    return length + TAG_LEN;
  }

  command error_t Sec.decrypt(CipherModeContext *cc, uint8_t iv, uint8_t *cipher_blocks, uint8_t length, 
                              uint8_t *plain_blocks, uint8_t *tag, uint8_t *valid) {
    uint8_t attempts_left = 63;
    while (attempts_left-- && ((cc->iv[7] & LNB_MASK(IV_BITS)) != (iv & LNB_MASK(IV_BITS)))){
      incrementIV(cc->iv);
    }
    if (attempts_left == 0) return FAIL;
    PRINTF("IV now = %d\n", cc->iv[7]);
    call CipherMode.decrypt(cc, cipher_blocks, plain_blocks,
                              length, tag, valid);
    return *valid;
  }

  error_t incrementIV(uint8_t *iv_block) {
    uint8_t i;
    for (i = 7; i >= 0; i--) {
      iv_block[i]++;
      if (iv_block[i]) return SUCCESS;
    }
    return FAIL;
  }

}
