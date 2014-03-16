/* KNoT Protocol definition
*
* Hardware and link/transport level independent protocol definition
*
* author Fergus William Leahy
*/ 
#ifndef KNOT_PROTOCOL_H
#define KNOT_PROTOCOL_H
#include <stdint.h>

//Sensor type
#define TEMP   1
#define HUM    2
#define SWITCH 3
#define LIGHT  4

/* Packet command types */
#define QUERY    1
#define QACK     2
#define CONNECT  3
#define CACK     4
#define RSYN     5
#define RACK     6
#define DISCONNECT 7
#define DACK     8
#define CMD      9
#define CMDACK  10
#define PING    11
#define PACK    12
#define SEQNO   13
#define SEQACK  14
#define RESPONSE 16

#define ASYM_QUERY 17
#define ASYM_RESPONSE 18
#define ASYM_RESP_ACK 19
#define ASYM_KEY_REQ  21
#define ASYM_KEY_RESP 22


#define CMD_LOW QUERY
#define CMD_HIGH RESPONSE		/* change this if commands added */

/* =======================*/

#define MAX_PACKET_SIZE    110
#define NO_PAYLOAD          0
#define MAX_DATA_SIZE      100
#define RESPONSE_DATA_SIZE 16
#define SYM_KEY_SIZE       10
#define ASYM_SIZE          84
#define NAME_SIZE          16
#define MAC_SIZE            4
#define E_NONCE_SIZE       45 /* 4(nonce) + 20(KEY_SIZE) + 1 + 20(HMAC) */ 
#define E_KEY_SIZE         55 /* 4(nonce) + 10(SYM_KEY_SIZE)+ 20(KEY_SIZE) + 1 + 20(HMAC) */
const char *cmdnames[23] = {"DUMMY0", "QUERY", "QACK","CONNECT", "CACK", 
                            "RSYN", "RACK", "DISCONNECT", "DACK",
                            "COMMAND", "COMMANDACK", "PING", "PACK", "SEQNO",
                            "SEQACK", "DUMMY1", "RESPONSE", "ASYM_QUERY",
                            "ASYM_RESP", "ASYM_RESP_ACK", "DUMMY2", 
                            "ASYM_KEY_REQ", "ASYM_KEY_RESP"};
typedef nx_struct chan_header {
   nx_uint8_t src_chan_num;
   nx_uint8_t dst_chan_num;
} ChanHeader;

typedef nx_struct payload_header {
   nx_uint16_t seqno;   /* sequence number */
   nx_uint8_t cmd;	/* message type */
} PayloadHeader;

typedef nx_struct data_header {
   nx_uint8_t tlen;	/* total length of the data */
} DataHeader;

typedef nx_struct data_payload {		/* template for data payload */
   PayloadHeader hdr;
   DataHeader dhdr;
   nx_uint8_t data[MAX_DATA_SIZE];	/* data is address of MAX_DATA_SIZE bytes */
} DataPayload;

/*********************/
/* Asymmetric Packet */
typedef nx_struct pubKey {
   nx_uint16_t x[10];
   nx_uint16_t y[10];
} PubKey; /* 40bytes */

typedef nx_struct sig {
   nx_uint16_t r[11];
   nx_uint16_t s[11];
} Signature; /* 42bytes */

typedef nx_struct pkc {
   PubKey pubKey;
   Signature sig;
} PKC; /* 80bytes */

typedef nx_struct asym_query_payload {
   PKC pkc;
   nx_uint8_t flags; /* handshake/cipherSpec? */
} AsymQueryPayload; /* 81bytes */

typedef nx_struct asym_resp_ack_payload {
   nx_uint8_t flags;
} AsymRespACKPayload; /* 81bytes */

typedef nx_struct asym_request_payload {
   nx_uint8_t e_nonce[E_NONCE_SIZE];
   Signature sig;
} AsymKeyRequestPayload; /* 85bytes */

typedef struct asym_key_payload {
   uint32_t nonce;
   nx_uint8_t sKey[10];
} AsymKeyPayload;

typedef nx_struct asym_key_tx_payload {
   nx_uint8_t e_payload[E_KEY_SIZE];
   Signature sig;
} AsymKeyRespPayload;

/********************/
/* Symmetric Packet */
typedef nx_struct sec_header {
   nx_uint8_t tag[MAC_SIZE];
} SSecHeader;

typedef nx_struct symmetric_secure_data_payload {
   nx_uint8_t flags;
   /* 1 byte Pad */   
   SSecHeader sh;
   ChanHeader ch;
   DataPayload dp;
} SSecPacket;

/****************/
/* Plain Packet */
typedef nx_struct plain_data_payload {
   ChanHeader ch;
   DataPayload dp;
} PDataPayload;

typedef nx_struct packet {
   nx_uint8_t flags;
   ChanHeader ch;
   DataPayload dp;
} Packet;

/********************/
/* Message Payloads */

typedef nx_struct query{
   nx_uint8_t type;
   nx_uint8_t name[NAME_SIZE];
}QueryMsg;

typedef nx_struct query_response{
   nx_uint16_t id;
   nx_uint16_t rate;
   nx_uint8_t type;
   nx_uint8_t name[NAME_SIZE];
}QueryResponseMsg;

typedef nx_struct connect_message{
   nx_uint16_t rate;
}ConnectMsg;

typedef nx_struct cack{
   nx_uint8_t accept;
}ConnectACKMsg;

typedef nx_struct response{
   nx_uint8_t data[MAX_DATA_SIZE];
}ResponseMsg;

typedef nx_struct serial_query_response{
   nx_uint8_t type;
   nx_uint16_t rate;
   nx_uint8_t name[NAME_SIZE];
   nx_uint8_t src;
}SerialQueryResponseMsg;

typedef nx_struct serial_response{
   nx_uint16_t data;
   nx_uint8_t src;
}SerialResponseMsg;

typedef nx_struct serial_connect{
   nx_uint8_t addr;
   nx_uint8_t rate;
}SerialConnect;

typedef nx_struct serial_cack{
   nx_uint8_t accept;
   nx_uint8_t src;
}SerialConnectACKMsg;

#endif /* KNOT_PROTOCOL_H */