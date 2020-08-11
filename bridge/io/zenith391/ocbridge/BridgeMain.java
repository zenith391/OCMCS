package io.zenith391.ocbridge;

import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.Reader;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.net.SocketOptions;
import java.util.HashMap;
import java.util.Random;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

public class BridgeMain {

	public static final String MAIN_TOKEN = "MCServerOnOC";
	public static final int MAIN_PORT = 25565;
	
	public static HashMap<String, Socket> tokens = new HashMap<>();
	public static ServerSocket listener;
	public static OutputStreamWriter mainWriter;
	
	public static ExecutorService clientExecutor = 
			Executors.newCachedThreadPool();
	public static ExecutorService listenerExecutor = 
			Executors.newCachedThreadPool();
	
	
	// Read null-terminated string
	public static String readString(Reader read, Socket sock) throws IOException {
		while (!read.ready()) {
			Thread.onSpinWait();
			if (sock.isClosed()) {
				throw new IOException("socket closed");
			}
		}
		String s = "";
		while (read.ready()) {
			char ch = (char) read.read();
			if (ch == 0) break;
			s = s + ch;
		}
		return s;
	}
	
	public static String generateToken() {
		Random rnd = new Random();
		StringBuilder sb = new StringBuilder();
		for (int i = 0; i < 5; i++) {
			char ch = (char) (rnd.nextInt(126-32) + 32);
			sb.append(ch);
		}
		return sb.toString();
	}
	
	public static void listen(Reader read, OutputStreamWriter writer, Socket sock) throws Exception {
		writer.write("l");
		writer.flush();
		listener = new ServerSocket(MAIN_PORT);
		while (true) {
			Socket s = listener.accept();
			String token = generateToken();
			tokens.put(token, s);
			writer.write("c" + token);
			writer.flush();
		}
	}
	
	static boolean listening = false;
	
	public static void server() throws Exception {
		ServerSocket ss = new ServerSocket(3330);
		while (true) {
			Socket sock = ss.accept();
			sock.setTcpNoDelay(true);
			Logger.info("Incoming connection");
			try {
				InputStream in = sock.getInputStream();
				OutputStream out = sock.getOutputStream();
				InputStreamReader reader = new InputStreamReader(sock.getInputStream());
				OutputStreamWriter writer = new OutputStreamWriter(sock.getOutputStream());
				
				Logger.debug("Retrieving token");
				String token = readString(reader, sock);
				Logger.debug("Checking token \"" + token + "\"");
				
				boolean validated = false;
				boolean mainConn = true;
				if (MAIN_TOKEN.equals(token)) {
					writer.write("o");
					writer.flush();
					Logger.debug("Valid token");
					validated = true;
				} else if (tokens.containsKey(token)) {
					writer.write("o");
					writer.flush();
					Logger.debug("Valid socket token");
					mainConn = false;
					validated = true;
				}
				
				if (!validated) {
					writer.write("n");
					writer.flush();
					sock.close();
					Logger.debug("Invalid token!");
					return;
				}
				
				if (mainConn) {
					mainWriter = writer;
					clientExecutor.submit(() -> {
						try {
							while (true) {
								if (sock.isClosed()) {
									if (listener != null) listener.close();
									listener = null;
									break;
								} else {
									int cmd = reader.read();
									if (cmd == -1 || cmd == 'e') {
										sock.close();
									} else if (cmd == 'n') {
										Logger.debug("Received ping response");
										for (int i = 0; i < 5; i++) {
											reader.read(); // discard
										}
									} else if (cmd == 'l'/* && !listening*/) {
										listenerExecutor.submit(() -> {
											try {
												if (listener != null) {
													listener.close();
												}
												listen(reader, writer, sock);
											} catch (SocketException e) {
												return;
											} catch (Exception e) {
												e.printStackTrace();
											}
										});
										listening = true;
									} else {
										Logger.debug("Invalid command: " + cmd);
									}
								}
								Thread.onSpinWait();
							}
							Logger.info("Main socket closed");
							listening = false;
						} catch (Exception e) {
							e.printStackTrace();
						}
					});
				} else {
					Socket s = tokens.get(token);
					s.setTcpNoDelay(true);
					clientExecutor.submit(() -> {
						Logger.info("Write ready");
						try {
							OutputStream o = s.getOutputStream();
							byte[] buf = new byte[8192];
							while (!s.isClosed()) {
								int b = in.read(buf);
								o.write(buf, 0, b);
							}
						} catch (IOException e) {
							if (!e.getMessage().equals("Socket closed") && !e.getMessage().equals("Connection reset")) {
								e.printStackTrace();
							}
						}
						Logger.info("Socket write closed");
					});
					clientExecutor.submit(() -> {
						Logger.info("Read ready");
						try {
							InputStream r = s.getInputStream();
							byte[] buf = new byte[4096];
							while (!s.isClosed()) {
								int b = r.read(buf);
								if (b == -1) {
									mainWriter.write("d" + token);
									mainWriter.flush();
									s.close();
									sock.close();
									System.out.println("CLOSE!");
									break;
								}
								out.write(buf, 0, b);
							}
						} catch (IOException e) {
							e.printStackTrace();
						}
						Logger.info("Socket read closed");
					});
				}
			} catch (Exception e) {
				e.printStackTrace();
			}
		}
	}
	
	public static void main(String[] args) {
		try {
			Logger.info("Server available on port " + MAIN_PORT + ". Bridge on 3330");
			Logger.info("The token is " + MAIN_TOKEN);
			server();
		} catch (Exception e) {
			e.printStackTrace();
		}
	}

}
