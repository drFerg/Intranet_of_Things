GEN=DataPayloadMsg.java
STRUCTS=plain_data_payload
all: client.jar

serial:
	java net.tinyos.sf.SerialForwarder -comm serial@/dev/ttyUSB1:telosb &

client.jar: KNoTClient.class
	jar cf $@ *.class

DataPayloadMsg.java: ../lib/KNoTProtocol.h
	mig -target=null $(CFLAGS) -java-classname=DataPayloadMsg java Payloads.h plain_data_payload -o $@

SerialResponseMsg.java: ../lib/KNoTProtocol.h
	mig -target=null $(CFLAGS) -java-classname=SerialResponseMsg java Payloads.h serial_response -o $@

#Constants.java: ../TinyBlogMsg.h
#	ncg -target=null $(CFLAGS) -java-classname=Constants java ../TinyBlogMsg.h DIRECT_MESSAGE DATA_SIZE POST_TWEET ADD_USER GET_TWEETS INTEREST TWEET_EVENT -o $@


KNoTClient.class: $(wildcard *.java) $(GEN)
	javac *.java

clean:
	rm -f *.class $(GEN)

veryclean: clean
	rm tinyblogclient.jar
