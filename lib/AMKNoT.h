#ifndef AM_KNOT_H
#define AM_KNOT_H
enum {
  AM_KNOT_MESSAGE = 10,
  DEFAULT_MESSAGE_SIZE = 40
};

/* Number of bytes per message. If you increase this, you will have to increase the message_t size,
   by setting the macro TOSH_DATA_LENGTH
   See $TOSROOT/tos/types/message.h
 */
enum {
  DATA_SIZE = 40
};
#endif /* AM_KNOT_H */