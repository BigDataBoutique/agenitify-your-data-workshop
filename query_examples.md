# Verified question -> SQL examples (few-shot)

These pairs are injected into the agent's system prompt to teach it the
conventions of this database. After the schema itself, a small set of correct
examples is the biggest lever on text2sql accuracy.

Rules of thumb:
- Only add SQL you have actually run and verified against the real database.
- Cover the patterns that matter for your data: joins, date filters, the
  cents->dollars convention, status value mappings, aggregation, GROUP BY.
- 5-15 representative examples is plenty; quality beats quantity.

---

**Q: How many active customers are on the enterprise plan?**

```sql
SELECT count(*)
FROM customers
WHERE status = 'active' AND plan = 'enterprise';
```

**Q: What was total paid revenue in dollars last month?**

```sql
SELECT sum(total_cents) / 100.0 AS revenue_dollars
FROM orders
WHERE status = 'paid'
  AND created_at >= date_trunc('month', current_date) - interval '1 month'
  AND created_at <  date_trunc('month', current_date);
```

**Q: Who are the top 5 customers by lifetime paid spend?**

```sql
SELECT c.name, sum(o.total_cents) / 100.0 AS lifetime_dollars
FROM customers c
JOIN orders o ON o.customer_id = c.id
WHERE o.status = 'paid'
GROUP BY c.id, c.name
ORDER BY lifetime_dollars DESC
LIMIT 5;
```

**Q: Which products sold the most units in paid orders?**

```sql
SELECT oi.product, sum(oi.quantity) AS units
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE o.status = 'paid'
GROUP BY oi.product
ORDER BY units DESC;
```
