import net.tinyos.message.*;
import net.tinyos.util.*;
import java.io.*;
import java.util.Scanner;



public class KNoTClient implements MessageListener
{

    MoteIF mote;
    int MYID = 0;
    int MOTEID = 1;
    short seqno = 1;

    private void cli(){
        Scanner input = new Scanner(System.in);
        System.out.print(">>");
        String command = input.next();
        while (!command.equals("quit")){
            if (command.equals("q") || command.equals("query")){
                query();
            }
            else if (command.equals("c") || command.equals("connect")){
                connect(input.nextInt(), input.nextInt());
            }
            else if (command.equals("help")){
                System.out.println("Help:\n" +
                                   "tweet <message>\n" + 
                                   "get\t(gets followed tweets)\n" +
                                   "follow <id>\n" +
                                   "connect <id> (sets tweet node)");          
            }
            System.out.print(">>");
            command = input.next();
        }
        input.close();
        System.exit(0);
    }

    /* Main entry point */
    void run() {
        mote = new MoteIF(PrintStreamMessenger.err);
        mote.registerListener(new DataPayloadMsg(), this);
        cli();
    }

    short[] convertStringToShort(String s){
        short [] text = new short[s.length()+1];
        int i = 0;
        for (; i < s.length(); i++){
            text[i] = (new Integer(s.charAt(i))).shortValue();
        }
        text[i] = 4;
        return text;
    }

    String convertShortToString(short[] s, short len){
        String text = "";
        for (short i = 0; i < len; i++){
            if (s[i] == 4)continue;
            text += (char)s[i];
        }
        return text;
    }

    void query(){
        System.out.println("Sending query");
        DataPayloadMsg msg = new DataPayloadMsg();
        msg.set_ch_src_chan_num((short) 0);
        msg.set_ch_dst_chan_num((short) 0);
        msg.set_dp_hdr_seqno((short) 0);
        msg.set_dp_hdr_cmd((short) 1);
        msg.set_dp_dhdr_tlen((short) 17);
        msg.set_dp_data(convertStringToShort("1Client\0"));
        sendMsg(msg);
    }

    void connect(int chan, int rate){
        System.out.println("Initiating connection to " + addr + " at " + rate);
        DataPayloadMsg msg = new DataPayloadMsg();
        msg.set_ch_src_chan_num((short) chan);
        msg.set_ch_dst_chan_num((short) 0);
        msg.set_dp_hdr_seqno((short) 0);
        msg.set_dp_hdr_cmd((short) 3);
        msg.set_dp_dhdr_tlen((short) 2);
        short data[] = {(short)0, (short)rate};
        msg.set_dp_data(data);
        sendMsg(msg);
    }
    // void getTweets(){
    //     System.out.printf("Node %d: Getting tweets...\n",MOTEID);
    //     TinyBlogMsg msg = new TinyBlogMsg();
    //     msg.set_action(GET_TWEETS);
    //     msg.set_destMoteID(MOTEID);
    //     msg.set_nchars((short)0);
    //     sendMsg(msg);
    // }
    // void tweet(String text){
    //     if (text.length() >100){
    //         System.out.println("Tweet to long, needs to be < 101 chars");
    //         return;
    //     }
    //     System.out.println("Tweet: " + text);
    //     System.out.printf("Node %d: Sending tweet...", MOTEID);
    //     short[] data = convertStringToShort(text);
    //     short len = (short)data.length;
    //     TinyBlogMsg msg = new TinyBlogMsg();
    //     msg.set_action(POST_TWEET);
    //     msg.set_destMoteID(MOTEID);
    //     msg.set_data(data);
    //     msg.set_nchars(len);
    //     sendMsg(msg);
    //     System.out.println("sent!");
    // }

    // void directMessage(int dest, String text){
    //     if (text.length() >100){
    //         System.out.println("Tweet to long, needs to be < 101 chars");
    //         return;
    //     }
    //     System.out.println("Direct msg: " + text);
    //     System.out.printf("Node %d: Sending message...", MOTEID);
    //     short[] data = convertStringToShort(text);
    //     short len = (short)data.length;
    //     TinyBlogMsg msg = new TinyBlogMsg();
    //     msg.set_action(DIRECT_MESSAGE);
    //     msg.set_destMoteID(dest);
    //     msg.set_data(data);
    //     msg.set_nchars(len);
    //     sendMsg(msg);
    //     System.out.println("sent!");

    // }


    public synchronized void messageReceived(int dest_addr, Message msg) {
        if (msg instanceof DataPayloadMsg) {
            System.out.println("Received a packet");
            if (((DataPayloadMsg)msg).get_dp_hdr_cmd() == 5){
                System.out.println("Received data: Temp is: ");
            }
        }
        // if (msg instanceof TinyBlogMsg) {
        //     TinyBlogMsg tbmsg = (TinyBlogMsg)msg;
        //     if (tbmsg.get_action() == RETURN_TWEETS){
        //         System.out.printf("Node %d tweeted: %s\nMood = %d\nseqno: %d\n", tbmsg.get_sourceMoteID(), 
        //             convertShortToString(tbmsg.get_data(),tbmsg.get_nchars()), tbmsg.get_mood(),tbmsg.get_seqno());
        //     } else if(tbmsg.get_action() == DIRECT_MESSAGE && tbmsg.get_destMoteID() == MYID ){
        //         System.out.printf("Node %d direct messaged you: %s\n\nseqno: %d\n", tbmsg.get_sourceMoteID(), 
        //             convertShortToString(tbmsg.get_data(),tbmsg.get_nchars()),tbmsg.get_seqno());
        //     }else if (tbmsg.get_sourceMoteID() != MOTEID ){
        //         //System.out.println("Received a msg");
        //         return;
        //     }
        // }
        // System.out.print(">>");
    }

    /* The user wants to set the interval to newPeriod. Refuse bogus values
       and return false, or accept the change, broadcast it, and return
       true */

    /* Broadcast a version+interval message. */
    void sendMsg(DataPayloadMsg msg) {

        // msg.set_sourceMoteID(MYID);
        // msg.set_seqno(seqno++);
        // msg.set_hopCount((short)6);
        try {
            mote.send(MOTEID, msg);
        }
        catch (IOException e) {
            System.out.println(e.getMessage());
            System.out.println("Cannot send message to mote");
        }
    }

    /* User wants to clear all data. */


    public static void main(String[] args) {
        KNoTClient me = new KNoTClient();
        me.run();
    }
}
