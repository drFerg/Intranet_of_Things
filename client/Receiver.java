import java.io.*;
import jCache.*;
class Receiver implements Runnable {
    private Service service;
    private KNoTClient client;

    public Receiver (Service s, KNoTClient k){
        service = s;
        client = k;
    }

    public void run() {
        try {
            Message query;
            while ((query = service.query()) != null) {
                String s = query.getContent();
                //System.out.println(s);
                client.markEnd(System.currentTimeMillis());
                query.getConnection().response("OK");
            }
        } catch (IOException e) {
            System.exit(1);
        }
    }
}

