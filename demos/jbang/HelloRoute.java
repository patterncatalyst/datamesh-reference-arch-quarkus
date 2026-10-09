///usr/bin/env jbang "$0" "$@" ; exit $?
//JAVA 25+
//DEPS org.apache.camel:camel-main:4.22.1
//DEPS org.apache.camel:camel-timer:4.22.1
//DEPS org.apache.camel:camel-log:4.22.1
//DEPS org.slf4j:slf4j-simple:2.0.20
//JAVA_OPTIONS -Dorg.slf4j.simpleLogger.logFile=System.out

// demos/jbang/HelloRoute.java — "bare" toolchain demo source.
//
// A single self-contained Camel route with no pom.xml and no Maven module:
// `jbang demos/jbang/HelloRoute.java` resolves the //DEPS above from Maven
// Central and runs main() below. Every dependency is pinned to a supported
// stable release: Camel 4.22.1 (the latest patch on the 4.22 line that the
// quarkus-camel-bom 3.40.1 platform pins) and slf4j-simple 2.0.20. The script
// runs from a local file only — no remote catalog alias or GitHub-hosted
// launcher is fetched, so jbang has nothing to ask the presenter to trust.
//
// Pipeline: a one-shot timer produces a body, a processor uppercases and
// prefixes it (a trivial EIP-style content transform), and the result is
// logged. demo-jbang-prototype.sh asserts the exact marker string appears in
// the output.
import org.apache.camel.builder.RouteBuilder;
import org.apache.camel.main.Main;

public class HelloRoute extends RouteBuilder {

    public static void main(String[] args) throws Exception {
        Main main = new Main();
        main.configure().addRoutesBuilder(new HelloRoute());
        // Stop after the timer's single message; 90 s ceiling covers a cold
        // dependency cache.
        main.configure().withDurationMaxMessages(1);
        main.configure().withDurationMaxSeconds(90);
        main.run(args);
    }

    @Override
    public void configure() throws Exception {
        from("timer:prototype?repeatCount=1")
            .setBody(constant("hello from a jbang prototype"))
            .process(exchange -> {
                String body = exchange.getIn().getBody(String.class);
                exchange.getIn().setBody("JBANG_PROTOTYPE_OK: " + body.toUpperCase());
            })
            .to("log:prototype?showBody=true&showHeaders=false");
    }
}
