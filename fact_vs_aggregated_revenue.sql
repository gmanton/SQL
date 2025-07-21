WITH params AS (
    SELECT
        '2025-07-01' AS period
),

filtered_daily_stats AS (
    SELECT 
        ds.partner_id, 
        ds.project_id, 
        ds.date, 
        ds.period, 
        SUM(ds.purchases) AS purchases, 
        SUM(ds.refunds) AS refunds, 
        SUM(ds.promo_cost) AS promo_cost, 
        SUM(ds.primary_revenue) AS primary_revenue, 
        SUM(ds.secondary_revenue) AS secondary_revenue, 
        SUM(ds.actions) AS actions
    FROM daily_stats ds
    JOIN params
        ON ds.period = params.period
    GROUP BY ds.partner_id, ds.project_id, ds.date
),

filtered_partners AS (
    SELECT 
        p.id, 
        p.name, 
        COALESCE(GROUP_CONCAT(DISTINCT pt.name SEPARATOR ', '), 'None') AS tags,
        p.role, 
        p.status, 
        ps.source_type
    FROM partners p
    LEFT JOIN partners_tags_map ptm ON ptm.partner_id = p.id 
    LEFT JOIN partner_tags pt ON ptm.tag_id = pt.id
    JOIN partner_settings ps ON p.id = ps.partner_id
    GROUP BY p.id, p.name
),

filtered_action_stats AS (
    SELECT 
        asd.partner_id, 
        asd.project_id, 
        asd.date, 
        SUM(asd.actions) AS actions, 
        SUM(asd.revenue) AS primary_revenue, 
        SUM(asd.secondary_revenue) AS secondary_revenue
    FROM action_stats asd
    JOIN params
        ON asd.period = params.period
    WHERE asd.partner_id IN (SELECT partner_id FROM filtered_daily_stats)
    GROUP BY asd.partner_id, asd.project_id, asd.date
),

filtered_transaction_stats AS (
    SELECT 
        ts.partner_id, 
        ts.project_id, 
        ts.date,
        SUM(CASE WHEN type IN (1) THEN ts.amount ELSE 0 END) AS purchases,  
        SUM(CASE WHEN type IN (2) THEN ts.amount ELSE 0 END) AS refunds, 
        SUM(CASE WHEN type IN (4) THEN ts.amount ELSE 0 END) AS promo_cost
    FROM transaction_stats ts
    JOIN params
        ON ts.period = params.period
    WHERE ts.partner_id IN (SELECT partner_id FROM filtered_daily_stats)
    GROUP BY ts.partner_id, ts.project_id, ts.date
)

SELECT
    fds.partner_id,
    fp.name, fp.tags, fp.role, fp.status, 
    fds.project_id, fp.source_type, fds.date, 

    COALESCE(fas.primary_revenue, 0) AS action_primary_revenue, 
    COALESCE(fds.primary_revenue, 0) AS daily_primary_revenue, 
    COALESCE(fds.primary_revenue, 0) - COALESCE(fas.primary_revenue, 0) AS primary_revenue_diff,

    COALESCE(fas.secondary_revenue, 0) AS action_secondary_revenue, 
    COALESCE(fds.secondary_revenue, 0) AS daily_secondary_revenue,
    COALESCE(fas.secondary_revenue, 0) - COALESCE(fds.secondary_revenue, 0) AS secondary_revenue_diff,

    COALESCE(fts.purchases, 0) AS transaction_purchases, 
    COALESCE(fds.purchases, 0) AS daily_purchases,
    COALESCE(fts.purchases, 0) - COALESCE(fds.purchases, 0) AS purchases_diff,

    COALESCE(fts.refunds, 0) AS transaction_refunds, 
    COALESCE(fds.refunds, 0) AS daily_refunds,
    COALESCE(fts.refunds, 0) - COALESCE(fds.refunds, 0) AS refunds_diff,

    COALESCE(fts.promo_cost, 0) AS transaction_promo_cost, 
    COALESCE(fds.promo_cost, 0) AS daily_promo_cost,
    COALESCE(fts.promo_cost, 0) - COALESCE(fds.promo_cost, 0) AS promo_cost_diff

FROM filtered_daily_stats fds

LEFT JOIN filtered_action_stats fas
    ON fds.partner_id = fas.partner_id
    AND fds.project_id = fas.project_id
    AND fds.date = fas.date

LEFT JOIN filtered_transaction_stats fts
    ON fds.partner_id = fts.partner_id
    AND fds.project_id = fts.project_id
    AND fds.date = fts.date

LEFT JOIN filtered_partners fp
    ON fds.partner_id = fp.id

WHERE fds.date < CURRENT_DATE
  AND fp.tags NOT LIKE ("%tech%")

HAVING
    action_primary_revenue != daily_primary_revenue
 OR action_secondary_revenue != daily_secondary_revenue
 OR transaction_purchases != daily_purchases
 OR transaction_refunds != daily_refunds
 OR transaction_promo_cost != daily_promo_cost

ORDER BY fds.date
;
