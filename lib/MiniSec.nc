interface MiniSec {

	command error_t init();
	command error_t encrypt(uint8_t *data, uint8_t length, uint8_t *tag, 
								 uint8_t tag_length, uint8_t *iv_field);
	command error_t decrypt(uint8_t *cipher_blocks, uint8_t *plain_blocks, 
                                uint8_t cipher_len, uint8_t *taggy, 
                                uint8_t *iv_field, uint8_t *valid);
}