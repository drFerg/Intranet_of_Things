import net.tinyos.message.*;
import net.tinyos.util.*;
import java.io.*;
import java.util.Scanner;
import cache.*;

public class KNoTClient implements MessageListener
{

    MoteIF mote;
    int MYID = 0;
    int MOTEID = 1;
    short seqno = 1;
    static Service service;
    String serviceName = "Handler";
    int port;
    Connection conn;
    Receiver recvr;
    Thread recvrThread;

    private void cli(){
        Scanner input = new Scanner(System.in);
        System.out.print(">>");
        String command = input.next();
        while (!command.equals("quit")){
            if (command.equals("q") || command.equals("query")){
                query();
            }
            else if (command.equals("c") || command.equals("connect")){
                connect(input.nextInt(), input.nextInt(), input.nextInt());
            }
            else if (command.equals("help")){
                System.out.println("You're on your own :P");          
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
        try {
            SRPC srpc = new SRPC();
            service = srpc.offer(serviceName);
            //(new Thread(new HWDBClient())).start();
            conn = srpc.connect("localhost", 1234,"HWDB");
            port = srpc.details().getPort();
            recvr = new Receiver(service, this);
            recvrThread = new Thread(recvr);
            recvrThread.start();
            System.out.println(conn.call(String.format("SQL:create table Temp (t integer) 127.0.0.1 %d %s", port, serviceName)));
            System.out.println(conn.call(String.format("SQL:register \"subscribe temp to Temp; behavior { send(temp); }\" 127.0.0.1 %d %s", port, serviceName)));
        }
        catch (Exception e) {
            System.exit(1);
        }
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

    void connect(int chan, int addr, int rate){
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



    public synchronized void messageReceived(int dest_addr, net.tinyos.message.Message msg) {
        if (msg instanceof DataPayloadMsg) {
            System.out.print("Received data: Temp is: ");
            int val = ((DataPayloadMsg)msg).get_dp_data()[0];
            System.out.println(val);
            String cmd = String.format("SQL:insert into Temp values ('%d') 127.0.0.1 %d %s", val, port, serviceName);
            System.out.println(cmd);
            try {
                System.out.println(conn.call(cmd));
            } 
            catch (Exception e) {
                System.exit(1);
            }
            if (((DataPayloadMsg)msg).get_dp_hdr_cmd() == 16){
                System.out.print("Received data: Temp is: ");
                System.out.println(val);
            }
        }
        System.out.println(">> ");
    }

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

    public static void main(String[] args) {
        KNoTClient me = new KNoTClient();
        me.run();
    }
}
