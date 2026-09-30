-- Seed a few demo SKUs so InventoryService/CheckStock and the REST /stock
-- endpoints have something to answer on a fresh dev/test start. Loaded via
-- quarkus.hibernate-orm.sql-load-script (see application.properties), run
-- after schema drop-and-create.
INSERT INTO stock (sku, quantity_on_hand) VALUES ('WIDGET-1', 50);
INSERT INTO stock (sku, quantity_on_hand) VALUES ('WIDGET-2', 12);
INSERT INTO stock (sku, quantity_on_hand) VALUES ('GADGET-1', 0);
