#define MAX_PACKET_SIZE    42
#define NO_PAYLOAD          0
#define MAX_DATA_SIZE      32
#define RESPONSE_DATA_SIZE 16
#define NAME_SIZE          16
#define MAC_SIZE            4

enum {
  AM_PLAIN_DATA_PAYLOAD = 10,
  DEFAULT_MESSAGE_SIZE = 40
};

typedef nx_struct chan_header {
   nx_uint8_t src_chan_num;
   nx_uint8_t dst_chan_num;
} ChanHeader;

typedef nx_struct payload_header {
   nx_uint8_t seqno;   /* sequence number */
   nx_uint8_t cmd;  /* message type */
} PayloadHeader;

typedef nx_struct data_header {
   nx_uint8_t tlen; /* total length of the data */
} DataHeader;

typedef nx_struct data_payload {    /* template for data payload */
   PayloadHeader hdr;
   DataHeader dhdr;
   nx_uint8_t data[MAX_DATA_SIZE];  /* data is address of MAX_DATA_SIZE bytes */
} DataPayload;

typedef nx_struct sec_header {
   nx_uint8_t tag[MAC_SIZE];
} SSecHeader;

typedef nx_struct symmetric_secure_data_payload {
   nx_uint8_t flags;
   SSecHeader sh;
   ChanHeader ch;
   DataPayload dp;
} SSecPacket;

typedef nx_struct plain_data_payload {
   ChanHeader ch;
   DataPayload dp;
} PDataPayload;

typedef nx_struct packet {
   nx_uint8_t flags;
   nx_uint8_t data[MAX_PACKET_SIZE];
} Packet;