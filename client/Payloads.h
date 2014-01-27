#define MAX_DATA_SIZE 32

enum {
  AM_DATA_PAYLOAD = 10,
  DEFAULT_MESSAGE_SIZE = 40
};

typedef nx_struct payload_header {
   nx_uint8_t src_chan_num;
   nx_uint8_t dst_chan_num;
   nx_uint8_t seqno;   /* sequence number */
   nx_uint8_t cmd;	/* message type */
   nx_uint16_t chksum;
} PayloadHeader;

typedef nx_struct data_header {
   nx_uint16_t tlen;	/* total length of the data */
} DataHeader;

typedef nx_struct data_payload {		/* template for data payload */
   PayloadHeader hdr;
   DataHeader dhdr;
   nx_uint8_t data[MAX_DATA_SIZE];	/* data is address of `len' bytes */
} DataPayload;
