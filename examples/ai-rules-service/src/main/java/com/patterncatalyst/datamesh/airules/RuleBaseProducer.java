package com.patterncatalyst.datamesh.airules;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;

import org.kie.api.KieBase;
import org.kie.internal.utils.KieHelper;
import org.kie.internal.io.ResourceFactory;
import org.kie.api.io.ResourceType;

/**
 * Builds the plain embedded Drools {@link KieBase} once, from the
 * classpath DRL, and hands it out as a CDI singleton -- NOT the Kogito/KIE
 * Quarkus extension (that is explicitly out of scope).
 *
 * <p>{@link KieBase} is stateless and thread-safe and is meant to be built
 * once and reused; a fresh, short-lived {@code KieSession} is minted per
 * triage request from it (see {@link OrderTriageRoute}), fires its rules,
 * and is disposed immediately after.
 */
@ApplicationScoped
public class RuleBaseProducer {

    @Produces
    @ApplicationScoped
    public KieBase orderTriageKieBase() {
        KieHelper kieHelper = new KieHelper();
        kieHelper.addResource(
            ResourceFactory.newClassPathResource("rules/order-triage.drl"),
            ResourceType.DRL);
        return kieHelper.build();
    }
}
