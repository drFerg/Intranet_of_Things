interface BlockCipher{
	command error_t init(CipherContext * context, uint8_t blockSize, 
						 uint8_t keySize, uint8_t * key);
	async command error_t encrypt(CipherContext *context,
					     					   uint8_t * plainBlock,
					     					   uint8_t * cipherBlock);
	async command error_t decrypt(CipherContext * context,
					     uint8_t * cipherBlock,
					     uint8_t * plainBlock);
}