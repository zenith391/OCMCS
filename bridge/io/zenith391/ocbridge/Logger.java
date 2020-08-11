package io.zenith391.ocbridge;

public class Logger {

	public enum Level {
		DEBUG,
		INFO,
		WARN,
		ERROR;
	}
	
	static Level level = Level.DEBUG;
	
	public static void log(Level lvl, Object obj) {
		if (lvl.compareTo(level) >= 0) {
			System.out.println(obj);
		}
	}
	
	public static void info(Object obj) {
		log(Level.INFO, "INFO " + obj);
	}
	
	public static void warn(Object obj) {
		log(Level.WARN, "WARN " + obj);
	}
	
	public static void error(Object obj) {
		log(Level.ERROR, "ERROR " + obj);
	}
	
	public static void debug(Object obj) {
		log(Level.DEBUG, "DEBUG " + obj);
	}

}
