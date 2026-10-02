// demos/jbang/HelloRoute.java — "bare" toolchain demo
// source. A single self-contained Camel route with no pom.xml and no Maven
// reactor module: `jbang camel@apache/camel run HelloRoute.java` resolves
// Camel's runtime from Maven Central on first use and runs this route
// directly, exactly the "sketch an idea before committing to a module"
// workflow demo-jbang-prototype.sh exists to showcase.
//
// Pipeline: a one-shot timer produces a body, two .transform() steps
// (uppercase, then prefix) model a trivial EIP-style content transform, and
// the result is logged. demo-jbang-prototype.sh asserts the exact final
// marker string appears in stdout — positive content, not just "it ran".
import org.apache.camel.builder.RouteBuilder;

public class HelloRoute extends RouteBuilder {
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
