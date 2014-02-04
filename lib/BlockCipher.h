#ifndef BLOCK_CIPHER
#define BLOCK_CIPHER

#ifndef BLOCK_SIZE 
#define BLOCK_SIZE 8
#endif /* BLOCK_SIZE */

#ifndef PRECOMP_BLOCKS 
#define PRECOMP_BLOCKS 7
#endif /* PRECOMP_BLOCKS */

#ifndef TAG_LENGTH
#define TAG_LENGTH 4
#endif /* TAG_LENGTH */

typedef uint8_t Block[BLOCK_SIZE];

#endif /* BLOCK_CIPHER */