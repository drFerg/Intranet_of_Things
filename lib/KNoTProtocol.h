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


#define CMD_LOW QUERY
#define CMD_HIGH RESPONSE		/* change this if commands added */

/* =======================*/

/* Macro signifying payload of 0 length */
#define NO_PAYLOAD     0
#define MAX_DATA_SIZE 32
#define RESPONSE_DATA_SIZE 16
#define NAME_SIZE     16

const char *cmdnames[17] = {"DUMMY", "QUERY", "QACK","CONNECT", "CACK", 
                                 "RSYN", "RACK", "DISCONNECT", "DACK",
                                 "COMMAND", "COMMANDACK", "PING", "PACK", "SEQNO",
                                 "SEQACK", "DUMMY", "RESPONSE"};

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

typedef nx_struct sec_data_payload {    /* template for data payload */
   PayloadHeader hdr;
   DataHeader dhdr;
   nx_uint8_t tag[4];
   nx_uint8_t data[MAX_DATA_SIZE];  /* data is address of `len' bytes */
} SecDataPayload;

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