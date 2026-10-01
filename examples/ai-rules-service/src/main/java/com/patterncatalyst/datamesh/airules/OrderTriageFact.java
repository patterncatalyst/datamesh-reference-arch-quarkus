package com.patterncatalyst.datamesh.airules;

import java.math.BigDecimal;

/**
 * The Drools working-memory fact for one order triage request.
 *
 * <p>A plain mutable JavaBean (not a record) on purpose: the DRL rules in
 * {@code rules/order-triage.drl} read the classified fields via standard
 * getters and write the decision back onto this same fact via
 * {@code modify()} (see the rule file for why). Drools' MVEL-backed
 * constraint and action compilation (provided by {@code drools-mvel})
 * targets this JavaBean shape.
 *
 * <p>{@code category}, {@code priority}, and {@code riskSignal} are filled
 * in by {@link OrderTriageRoute} from the langchain4j classification step
 * <em>before</em> the fact is inserted into the {@code KieSession}.
 * {@code decision} and {@code reason} start {@code null} and are set by
 * whichever rule fires.
 */
public class OrderTriageFact {

    private String customerId;
    private String itemSku;
    private int quantity;
    private BigDecimal amount;

    private String category;
    private String priority;
    private String riskSignal;

    private String decision;
    private String reason;

    public String getCustomerId() {
        return customerId;
    }

    public void setCustomerId(String customerId) {
        this.customerId = customerId;
    }

    public String getItemSku() {
        return itemSku;
    }

    public void setItemSku(String itemSku) {
        this.itemSku = itemSku;
    }

    public int getQuantity() {
        return quantity;
    }

    public void setQuantity(int quantity) {
        this.quantity = quantity;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public String getPriority() {
        return priority;
    }

    public void setPriority(String priority) {
        this.priority = priority;
    }

    public String getRiskSignal() {
        return riskSignal;
    }

    public void setRiskSignal(String riskSignal) {
        this.riskSignal = riskSignal;
    }

    public String getDecision() {
        return decision;
    }

    public void setDecision(String decision) {
        this.decision = decision;
    }

    public String getReason() {
        return reason;
    }

    public void setReason(String reason) {
        this.reason = reason;
    }

    @Override
    public String toString() {
        return "OrderTriageFact[customerId=" + customerId
            + ", itemSku=" + itemSku
            + ", quantity=" + quantity
            + ", amount=" + amount
            + ", category=" + category
            + ", priority=" + priority
            + ", riskSignal=" + riskSignal
            + ", decision=" + decision
            + ", reason=" + reason
            + "]";
    }
}
