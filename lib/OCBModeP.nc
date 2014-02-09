/*
* ocb.c -- Implemented by TEd Krovetz (tdk@acm.org) -- Modified 2005.03.11
* This implementation is in the public domain. No warranty applies.
*
* This file needs an implementation of AES to work properly. It currently 
* uses "rijndael-alg-fst.c"by Barreto, Bosselaers and Rijmen, which should 
* be bundled with this implementation. (If not, search the Internet for
* "rijndael-fst-3.0.zip", or substitute your preffered implementation.)
*/

/*
* Adapted by Ghita Mezzour from C to nesC 
* 2014.02.04 Bug fixed, cleaned and updated to TinyOS 2.1.2 by Fergus Leahy
*/
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

module OCBModeP {
  provides interface OCBMode;
  uses interface BlockCipher as Cipher;
}
implementation
{
  /* there are many things hardcoded dependent on the blk size
  * don't expect the code to work just by changing the value
  * of BLOCK_SIZE
  */


  void xor_block(Block dst, Block src1, Block src2); 
  void shift_left(uint8_t *x);
  void shift_right(uint8_t *x);
  uint8_t num_trailing_zeros(uint8_t i);

  command error_t  OCBMode.init(CipherModeContext *context, uint8_t keySize, 
                                uint8_t *key, uint8_t tagLength, 
                                uint8_t preComputeBlocks) {
    uint8_t i, first_bit, last_bit;
    uint8_t tmp[] = {0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0};

    call Cipher.init(&(context->cc), BLOCK_SIZE, keySize, key); 

    /* precompute L[i] values. L[0] is synonym of L */
    call Cipher.encrypt(&(context->cc), tmp, tmp);
    for(i = 0; i <= PRECOMP_BLOCKS; i++) {
      memcpy(context->L[i], tmp, BLOCK_SIZE);//cpy tmp to L[i]
      first_bit = tmp[0] & 0x80u;
      shift_left(tmp);
      if(first_bit)
        tmp[BLOCK_SIZE - 1] ^= 0x1B; /* this value is dependant on the blk size */
    }

    /* precompute L_inv = L. x^{-1} */
    memcpy(tmp, context->L[0], BLOCK_SIZE);
    last_bit = tmp[BLOCK_SIZE - 1] & 0x01;
    shift_right(tmp);
    if(last_bit) {
      tmp[0] ^= 0x80;
      tmp[BLOCK_SIZE - 1] ^= 0x0D; /* this value depends on the blk size */
    }

    memcpy(context->L_inv, tmp, BLOCK_SIZE);
    return SUCCESS;
  }


  async command error_t OCBMode.encrypt(CipherModeContext *context, uint8_t *plainText, 
                                        uint8_t *cipherText, uint16_t pt_len, uint8_t *tag) {
    uint8_t i;
    Block tmp, tmp2;
    Block *pt_blk, *ct_blk;
    Block offset;
    Block checksum;

    i = 1;
    pt_blk = (Block *)plainText - 1;
    ct_blk = (Block *)cipherText - 1;
    memset(checksum, 0, BLOCK_SIZE);

    /* calculate R, aka Z[0] */
    xor_block(offset, context->iv, context->L[0]); 

    call Cipher.encrypt(&(context->cc), offset, offset);
    /*
    * Process blocks 1... m-1
    */
    while (pt_len > BLOCK_SIZE) {
      /* Update the Offset (Z[i] from Z[i-1]) */
      xor_block(offset, context->L[num_trailing_zeros(i)], offset);
      /* xor the plaintext Block Block with Z[i] */
      xor_block(tmp, offset, pt_blk[i]);
      /* Encipher the Block */
      call Cipher.encrypt(&(context->cc), tmp, tmp);
      /* xor Z[i] again, writing result to ciphertext pointer */
      xor_block(ct_blk[i], offset, tmp);
      /* Update checksum */
      xor_block(checksum, checksum, pt_blk[i]);
      /* Update loop variables */
      pt_len -= BLOCK_SIZE;
      i++;
    }
    /* Process last Block (m)*/
    /* Update Offset (Z[m] from Z[m-1]) */
    xor_block(offset, context->L[num_trailing_zeros(i)], offset);
    /* xor L . x^{-1} and Z[m] */
    xor_block(tmp, offset, context->L_inv);
    /* Add in final Block bit-length */
    tmp[BLOCK_SIZE-1] ^= (pt_len << 3);
    call Cipher.encrypt(&(context->cc), tmp, tmp);
    /* xor 'pt' with block-cipher output, copy valid bytes to 'ct' */
    memcpy(tmp2, pt_blk[i], pt_len);
    xor_block(tmp2, tmp2, tmp);
    memcpy(ct_blk[i], tmp2, pt_len);

    /* Add to checksum the pt_len bytes of plaintext followed by */ 
    /* the last (8 - pt_len) bytes of block-cipher output */
    memcpy(tmp, pt_blk[i], pt_len);
    xor_block(checksum, checksum, tmp);

    /* Calculate tag*/
    xor_block(checksum, checksum, offset);
    call Cipher.encrypt(&(context->cc), checksum, tmp);
    memcpy(tag, tmp, TAG_LENGTH);
    return SUCCESS;
  }

  async command error_t OCBMode.decrypt(CipherModeContext *context, uint8_t *cipherBlock,
                                        uint8_t *plainBlock, uint16_t ct_len, uint8_t *tag,
                                        uint8_t *valid) {
    uint8_t i;
    Block tmp, tmp2;
    Block *ct_blk, *pt_blk;
    Block offset;
    Block checksum;
    /* Initializations*/
    i = 1;                              /* Start with first Block              */
    ct_blk = (Block *)cipherBlock - 1;  /* These are adjusted so, for example, */
    pt_blk = (Block *)plainBlock - 1;   /* ct_blk[1] refers to the first Block */

    /* Zero checksum */
    memset(checksum, 0, BLOCK_SIZE);

    /* Calculate R, aka Z[0] */
    xor_block(offset, context->iv, context->L[0]);
    call Cipher.encrypt(&(context->cc), offset, offset);

    
    /* Process blocks 1 .. m-1 */
    while (ct_len > BLOCK_SIZE ) {
      /* Update Offset (Z[i] from Z[i-1]) */
      xor_block(offset, context->L[num_trailing_zeros(i)], offset);
      /* xor ciphertext Block with Z[i] */
      xor_block(tmp, offset, ct_blk[i]);
      /* Decipher the next block-cipher Block */
      call Cipher.decrypt(&(context->cc), tmp, tmp);
      /* xor Z[i] again, writing result to plaintext ponter */
      xor_block(pt_blk[i], offset, tmp);
      /* Update checksum */
      xor_block(checksum, checksum, pt_blk[i]);
      /* Update loop variables */
      ct_len -= BLOCK_SIZE ;
      i++;
    }
    /* Process last Block (m) */
    /* Update Offset (Z[m] from Z[m-1]) */
    xor_block(offset, context->L[num_trailing_zeros(i)], offset);
    /* xor L . x^{-1} and Z[m] */
    xor_block(tmp, offset, context->L_inv);
    /* Add in final Block bit-length */
    tmp[BLOCK_SIZE - 1] ^= (ct_len << 3);
    call Cipher.encrypt(&(context->cc), tmp, tmp);

    /* Form the final ciphertext block, C[m]  */
    memset(tmp2, 0, BLOCK_SIZE);
    memcpy(tmp2, ct_blk[i], ct_len);
    xor_block(tmp, tmp2, tmp);
    memcpy(pt_blk[i], tmp, ct_len);
    /* After the xor above, tmp will have ct_len bytes of plaintext  */
    /* then (8 - ct_len) block-cipher bytes, perfect for checksum.  */
    xor_block(checksum, checksum, tmp);

    /* Calculate tag */
    xor_block(checksum, checksum, offset);
    call Cipher.encrypt(&(context->cc),checksum, tmp); 
    *valid = (memcmp(tag, tmp, TAG_LENGTH) == 0 ? 1 : 0);
    return SUCCESS;
  }

  async command error_t OCBMode.initIncrementalDecrypt (CipherModeContext * context,
                                                        uint8_t *IV,
                                                        uint16_t length) {
    return FAIL;
  }

  async command error_t OCBMode.incrementalDecrypt (CipherModeContext *context,
                                                    uint8_t *ciphertext, 
                                                    uint8_t *plaintext,
                                                    uint16_t length,
                                                    uint16_t *done) {
    return FAIL;
  }


  /************************************************************
  * utilities functions                                      *
  ***********************************************************/
  void  xor_block(Block dst, Block src1, Block src2) {
    dst[0] = src1[0] ^ src2[0];
    dst[1] = src1[1] ^ src2[1];
    dst[2] = src1[2] ^ src2[2];
    dst[3] = src1[3] ^ src2[3];
    dst[4] = src1[4] ^ src2[4];
    dst[5] = src1[5] ^ src2[5];
    dst[6] = src1[6] ^ src2[6];
    dst[7] = src1[7] ^ src2[7];

  }

  void shift_left(uint8_t *x) {
    int i;
    for(i = 0; i < 7; i++) {
      x[i] = (x[i] << 1)| (x[i+1] & 0x80 ? 1 : 0) ;
    }
    x[7] = (x[7] << 1);
  }

  void shift_right(uint8_t *x) {
    int i;
    for(i = 7; i > 0; i--) {
      x[i] = (x[i] >> 1) | (x[i-1] & 1 ? 0x80u : 0);
    }
    x[0] = (x[0] >> 1);
  }

  uint8_t num_trailing_zeros(uint8_t i) {
    uint8_t rval = 0;
    while ((i & 1) == 0) {
      i >>= 1;
      rval++;
    }
    return rval;
  }
}

