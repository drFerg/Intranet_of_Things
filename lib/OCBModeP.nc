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
* adapted by Ghita Mezzour from C to nesC 
* can be used with any block cipher
*/



module OCBModeP {
  provides interface OCBMode;
  uses interface BlockCipher as cipher;
}
implementation
{
  /* there are many things hardcoded dependent on the blk size
   * don't expect the code to work just by changing the value
   * of BLOCK_SIZE
   */

  /* I am thinking of using a different interface that would allow the
   * choice of PRE_COMP_BLOCKS and TAG_LENGTH 
   * I feel that BlockCipherMode is not flexible enough for OCB, but
   * I don't know if we want to let the choice of these parameters to
   * the user, or not
   */
  
#define BLOCK_SIZE 8  
#define PRE_COMP_BLOCKS 7
#define TAG_LENGTH 4

  typedef uint8_t block[BLOCK_SIZE];
  block L[PRE_COMP_BLOCKS+1];
  block L_inv;
  uint8_t preCombBlks;
  //uint8_t tagLgth;

  void  xor_block(block dst,block src1,block src2); 
  void shift_left (uint8_t *x);
  void shift_right (uint8_t *x);
  uint8_t ntz(uint8_t i);
  void cpy_blk(uint8_t *des, uint8_t *src, uint8_t block_size);
  void zeros (uint8_t *buffer, uint8_t size);
  uint8_t cmp_buffer(uint8_t * buf1, uint8_t * buf2, uint8_t length);
  
  /* testing */
  void dumpBuffer(char * bufName, uint8_t * buf, uint8_t size);
  void dumpInt(char * intName, uint8_t nbre);
  
 command error_t  OCBMode.init(CipherModeContext * context,
				uint8_t keySize, 
				uint8_t * key,
				uint8_t tagLength, /* length of the tag in Bytes */
				uint8_t preCombBlocks) {
   uint8_t i, first_bit, last_bit;
   //uint8_t pl []={0,0,0,0,0,0,0,0};
   uint8_t tmp[]={0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0};

   uint8_t tmpP[] = {0xab,0x98,0x15, 0x30, 0x40, 0x91, 0x67, 0x85};
   uint8_t tmpC[]= {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}; 

   call cipher.init( (&(context->cc)) ,BLOCK_SIZE , keySize, key); 
   call cipher.encrypt(&(context->cc) , tmp,tmp  );
   
   /* test */
   call cipher.encrypt(&(context -> cc), tmpP, tmpC );
   dumpBuffer("test1 ciphertxt initialized to 0, tmpP", tmpP, 8);
   dumpBuffer("test1 tmpC", tmpC, 8);
   call cipher.encrypt(&(context -> cc), tmpP, tmpP);
   dumpBuffer("test2", tmpP, 8);
   /* end test */

   /* precompute L[i] values. L[0] is synonym of L */
   for(i=0; i<= PRE_COMP_BLOCKS; i++) {
     cpy_blk(L[i], tmp, BLOCK_SIZE);//cpy tmp to L[i]
     first_bit = tmp[0] & 0x80u;
     shift_left(tmp);
     if(first_bit)
       tmp[BLOCK_SIZE-1] ^= 0x1B; /* this value is dependant on the blk size */
   }
   
   /* precompute L_inv = L. x^{-1} */
   cpy_blk(tmp, L[0], BLOCK_SIZE);
   last_bit = tmp[BLOCK_SIZE - 1] & 0x01;
   shift_right(tmp);
   if(last_bit) {
     tmp[0] ^= 0x80;
     tmp[BLOCK_SIZE - 1] ^= 0x0D; /* this value depends on the blk size */
   }
   
   cpy_blk(L_inv, tmp, BLOCK_SIZE);
   
   preCombBlks = preCombBlocks;
   //tagLgth = tagLength;

   return SUCCESS;
 }

 
async command error_t OCBMode.encrypt(CipherModeContext * context,
					uint8_t * plainText, 
					uint8_t * cipherText,
					uint8_t * tag,
					uint16_t numBytes, 
					uint8_t * IV) {
   uint8_t i;
   block tmp, tmp2;
   block *pt_blk, *ct_blk;
   block offset;
   block checksum;
   uint16_t pt_len = numBytes;

   i = 1;
   pt_blk = (block *)plainText - 1;
   ct_blk = (block *)cipherText - 1;
   zeros(checksum, BLOCK_SIZE);

   /* calculate R, aka Z[0] */
   xor_block(offset, IV, L[0] ); 
   
   call cipher.encrypt(&(context->cc), offset, offset);
   /*
    * Process blocks 1... m-1
    */
   while (pt_len > BLOCK_SIZE) {
     
     /* Update the Offset (Z[i] from Z[i-1]) */
     xor_block(offset, L[ntz(i)] , offset);
     
     /* xor the plaintext block block with Z[i] */
     xor_block(tmp, offset, pt_blk[i] );
        
     /* Encipher the block */
     call cipher.encrypt (&(context->cc) ,  tmp, tmp);
     
     /* xor Z[i] again, writing result to ciphertext pointer */
     xor_block(ct_blk[i] , offset, tmp);
        
     /* Update checksum */
     xor_block(checksum, checksum, pt_blk[i]);

     /* Update loop variables */
     pt_len -= BLOCK_SIZE;
     i++;
   }
   
   /*
    * Process block m
    */
   
   /* Update Offset (Z[m] from Z[m-1]) */
   xor_block(offset, L[ntz(i)]  , offset);
    
   /* xor L . x^{-1} and Z[m] */
   xor_block(tmp, offset, L_inv);
   
   /* Add in final block bit-length */
   tmp[BLOCK_SIZE-1] ^= (pt_len << 3);

   call cipher.encrypt (& (context-> cc), tmp, tmp);

   /* xor 'pt' with block-cipher output, copy valid bytes to 'ct' */
   cpy_blk(tmp2, pt_blk[i]  , pt_len);
   xor_block(tmp2, tmp2, tmp);
   cpy_blk(ct_blk[i] , tmp2, pt_len);

   /* Add to checksum the pt_len bytes of plaintext followed by */ 
   /* the last (16 - pt_len) bytes of block-cipher output */
   cpy_blk(tmp, pt_blk[i] , pt_len);
   xor_block(checksum, checksum, tmp);
   
   /* 
    * Calculate tag
    */
   xor_block(checksum, checksum, offset);
   call cipher.encrypt(&(context->cc) , checksum, tmp);
   //cpy_blk(tag, tmp, (tagLgth << 3));
   cpy_blk(tag, tmp, 32);
   return SUCCESS;
   
 }
async command error_t OCBMode.decrypt(CipherModeContext * context,
				       uint8_t * cipherBlock,
				       uint8_t * tag,
				       uint8_t * plainBlock,
				       uint16_t numBytes, 
				       uint8_t * IV,
				       uint8_t * valid) {
  uint8_t i;
  uint16_t ct_len = numBytes;
  block tmp, tmp2;
  block *ct_blk, *pt_blk;
  block offset;
  block checksum;
  
  /* 
   * Initializations
   */
  i = 1;                      /* Start with first block              */
  ct_blk = (block *)cipherBlock - 1;   /* These are adjusted so, for example, */
  pt_blk = (block *)plainBlock - 1;   /* ct_blk[1] refers to the first block */
  
  /* Zero checksum */
  zeros(checksum,BLOCK_SIZE  );

  /* Calculate R, aka Z[0] */
  xor_block(offset, IV, L[0]);
  call cipher.encrypt (&(context -> cc), offset, offset);
    
  /*
   * Process blocks 1 .. m-1
   */
  while (ct_len > BLOCK_SIZE ) {

    /* Update Offset (Z[i] from Z[i-1]) */
    xor_block(offset,  L[ ntz(i)] , offset);

    /* xor ciphertext block with Z[i] */
    xor_block(tmp, offset, ct_blk[i] );
    
    /* Decipher the next block-cipher block */
    call cipher.decrypt ( &(context -> cc) , tmp, tmp);
            
    /* xor Z[i] again, writing result to plaintext ponter */
    xor_block(pt_blk [i], offset, tmp);
        
    /* Update checksum */
    xor_block(checksum, checksum, pt_blk[i]  );

    /* Update loop variables */
    ct_len -= BLOCK_SIZE ;
    i++;
  }

  /*
   * Process block m
   */

  /* Update Offset (Z[m] from Z[m-1]) */
  xor_block(offset, L[ntz(i)] , offset);
  
  /* xor L . x^{-1} and Z[m] */
  xor_block(tmp, offset, L_inv);

  /* Add in final block bit-length */
  tmp[BLOCK_SIZE - 1] ^= (ct_len << 3);
  
  call cipher.encrypt (&(context -> cc) , tmp, tmp);
    
  /* Form the final ciphertext block, C[m]  */
  zeros(tmp2, BLOCK_SIZE);
  cpy_blk(tmp2, ct_blk[i] , ct_len);
  xor_block(tmp, tmp2, tmp);
  cpy_blk(pt_blk[i] , tmp, ct_len);

  /* After the xor above, tmp will have ct_len bytes of plaintext  */
  /* then (8 - ct_len) block-cipher bytes, perfect for checksum.  */
  xor_block(checksum, checksum, tmp);

    
  /* 
   * Calculate tag
   */
  xor_block(checksum, checksum, offset);
  call cipher.encrypt(&(context -> cc),checksum, tmp); 
  //return (memcmp(tag, tmp, key->tag_len) == 0 ? 1 : 0);
  //dumpBuffer("*msg* tag", tag, 4);
  //dumpBuffer("*msg* tmp", tmp, 4);
  * valid = cmp_buffer(tag, tmp, TAG_LENGTH); 
  dumpInt("*msg* valid", *valid);
  //dumpBuffer("*msg* decrypted msg", plainBlock, 22);

  return SUCCESS;

}

async command error_t OCBMode.initIncrementalDecrypt (CipherModeContext * context,
						 uint8_t * IV,
						uint16_t length) {
   return SUCCESS;
 }

 async command error_t OCBMode.incrementalDecrypt (CipherModeContext * context,
					     uint8_t * ciphertext, 
					     uint8_t * plaintext,
					     uint16_t length,
					     uint16_t * done) {

    return SUCCESS;
  }


  /************************************************************
   * utilities functions                                      *
   ***********************************************************/
void  xor_block(block  dst,block src1, block src2) 
    {
      dst[0] = src1[0] ^ src2[0];
      dst[1] = src1[1] ^ src2[1];
      dst[2] = src1[2] ^ src2[2];
      dst[3] = src1[3] ^ src2[3];
      dst[4] = src1[4] ^ src2[4];
      dst[5] = src1[5] ^ src2[5];
      dst[6] = src1[6] ^ src2[6];
      dst[7] = src1[7] ^ src2[7];

    }
	
  void shift_left (uint8_t *x)
    {
      int i;
      for(i=0; i<7; i++) {
        x[i]= (x[i] << 1)| (x[i+1] & 0x80 ? 1 : 0) ;
      }
      x[7] = (x[7] << 1);
    }

  void shift_right (uint8_t *x)
    {
      int i;
      for(i=7; i>0; i--) {
        x[i]= (x[i] >> 1) | (x[i-1] & 1 ? 0x80u : 0);
      }
      x[0] = (x[0] >> 1);
    }

  uint8_t ntz(uint8_t i)
    {
      uint8_t rval = 0;
      while ((i & 1) == 0) {
        i >>= 1;
        rval++;
      }
      return rval;
    }


  void cpy_blk(uint8_t *des, uint8_t *src, uint8_t block_size)
    {
      uint8_t i;
      for (i=0; i< block_size  ; i++)
        des[i]=src[i];
    }
  void zeros (uint8_t *buffer, uint8_t size)
    {
      uint8_t i;
      for (i= 0; i<size ; i++) 
        buffer[i] = 0;
    }

   void dumpBuffer (char * bufName, uint8_t * buf, uint8_t size)
    {
      uint8_t b = 0;
      // fixme watch buffer overrun
      //char tmp[512];
      
      for (; b < size; b++) {
        dbg(DBG_USR1, "=> %s: 0x%x \n", bufName, buf[b] & 0xff);
      }
      dbg(DBG_USR1, "/n");
      //dbg(DBG_USR1, "%s: {%s}\n", bufName, tmp);
    }

   void dumpInt(char * intName, uint8_t nbre)
    {
      dbg(DBG_USR1, "=> %s: 0x%x.   ", intName, nbre);
    }

  uint8_t cmp_buffer(uint8_t * buf1, uint8_t * buf2, uint8_t length) {
    uint8_t i;
    for( i=0; i< length; i++) {
      if (buf1[i] != buf2[i])
        return 0;
    } 
    return 1;
  } 

}




