///usr/bin/env jbang "$0" "$@" ; exit $?
//JAVA 25+
//JAVA_OPTIONS --enable-native-access=ALL-UNNAMED

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.invoke.MethodHandle;
import java.nio.charset.StandardCharsets;

import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_LONG;

/**
 * Calls two libc functions through the Foreign Function & Memory API
 * (JEP 454, final in JDK 22): no JNI, no C glue, no native build step.
 * Resolves symbols from the platform C library via the linker's default
 * lookup, so it runs on Linux.
 */
public class PanamaFfm {

    public static void main(String[] args) throws Throwable {
        Linker linker = Linker.nativeLinker();
        SymbolLookup libc = linker.defaultLookup();

        // int getpid(void)
        MethodHandle getpid = linker.downcallHandle(
                libc.find("getpid").orElseThrow(),
                FunctionDescriptor.of(JAVA_INT));

        // size_t strlen(const char *s)
        MethodHandle strlen = linker.downcallHandle(
                libc.find("strlen").orElseThrow(),
                FunctionDescriptor.of(JAVA_LONG, ADDRESS));

        int nativePid = (int) getpid.invokeExact();
        System.out.println("PANAMA_GETPID=" + nativePid + " JVM_PID=" + ProcessHandle.current().pid());

        String text = "data mesh on Quarkus — héllo";
        // The arena owns the off-heap C string and frees it when it closes.
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment cString = arena.allocateFrom(text);
            long nativeLen = (long) strlen.invokeExact(cString);
            System.out.println("PANAMA_STRLEN=" + nativeLen
                    + " JAVA_LENGTH=" + text.getBytes(StandardCharsets.UTF_8).length);
        }
    }
}
