WITH params AS (
    SELECT 
        "2025-06-01" AS start_date, 
        "2025-06-30" AS end_date
),

filtered_user_daily_stats AS (
    SELECT 
        uds.user_id, 
        uds.partner_id, 
        uds.campaign_id, 
        uds.plan_id, 
        uds.project_id, 
        uds.date,
        u.id,
        u.registration_date, 
        u.confirmation_date, 
        u.is_duplicate, 
        u.first_purchase_amount / 100 AS first_purchase, 
        u.first_purchase_date,
        u.activation_date, 
        uds.period, 

        SUM(uds.partner_revenue) AS partner_revenue,
        SUM(uds.gross_revenue) AS gross_revenue, 
        SUM(uds.betting_revenue) AS betting_revenue, 
        SUM(uds.total_purchases) AS total_purchases, 
        SUM(uds.total_refunds) AS total_refunds, 
        SUM(uds.promo_cost) AS promo_cost,

        (
            CASE 
                WHEN uds.project_id = 1 THEN ROUND(((SUM(uds.gross_revenue) * 1) - SUM(uds.promo_cost) - (SUM(uds.total_purchases) - SUM(uds.total_refunds)) * 0.05), 0)
                WHEN uds.project_id = 3 THEN ROUND(((SUM(uds.gross_revenue) * 0.85) + (SUM(uds.betting_revenue) * 0.8) - SUM(uds.promo_cost) - (SUM(uds.total_purchases) - SUM(uds.total_refunds)) * 0.05), 0)
                WHEN uds.project_id = 5 THEN ROUND(((SUM(uds.gross_revenue) * 0.835) + (SUM(uds.betting_revenue) * 0.8) - SUM(uds.promo_cost) - (SUM(uds.total_purchases) - SUM(uds.total_refunds)) * 0.1), 0)
                WHEN uds.project_id = 6 THEN ROUND(((SUM(uds.gross_revenue) * 0.65) + (SUM(uds.betting_revenue) * 1) - SUM(uds.promo_cost) - (SUM(uds.total_purchases) - SUM(uds.total_refunds)) * 0.05), 0)
                WHEN uds.project_id = 10 THEN ROUND(((SUM(uds.gross_revenue) * 0.85) + (SUM(uds.betting_revenue) * 0.8) - SUM(uds.promo_cost) - (SUM(uds.total_purchases) - SUM(uds.total_refunds)) * 0.05), 0)
                ELSE 0 
            END
        ) / 100 AS net_revenue

    FROM user_daily_stats uds
    JOIN params
    LEFT JOIN users u 
        ON uds.user_id = u.id
        AND uds.project_id = u.project_id
        AND uds.plan_id = u.plan_id
    LEFT JOIN blocked_users bu
        ON uds.user_id = bu.user_id
    WHERE u.activation_date BETWEEN params.start_date AND params.end_date
      AND bu.user_id IS NULL
    GROUP BY 
        uds.user_id, 
        uds.campaign_id, 
        uds.partner_id, 
        uds.plan_id, 
        uds.project_id
),

filtered_plans AS (
    SELECT 
        id, 
        config, 
        type,
        CAST(JSON_VALUE(config, '$.required_first_purchase') AS DECIMAL(10,4)) AS required_first_purchase,
        CAST(JSON_VALUE(config, '$.required_orders') AS DECIMAL(10,4)) AS required_orders,
        CAST(JSON_VALUE(config, '$.required_total_purchase') AS DECIMAL(10,4)) AS required_total_purchase,
        CAST(JSON_VALUE(config, '$.escape_fee') AS DECIMAL(10,4)) AS escape_fee,
        CAST(JSON_VALUE(config, '$.fixed_reward') AS DECIMAL(10,4)) AS fixed_reward,
        CAST(JSON_VALUE(config, '$.percentage_reward') AS DECIMAL(10,4)) AS percentage_reward,
        CAST(JSON_VALUE(config, '$.required_active_days') AS DECIMAL(10,4)) AS required_active_days
    FROM plans
),

filtered_partner_personal_options AS (
    SELECT 
        COALESCE(partner_id, "None") AS partner_id, 
        COALESCE(plan_id, "None") AS plan_id, 
        fixed_reward AS po_fixed_reward,
        percentage_reward AS po_percentage_reward,
        start_date, 
        end_date 
    FROM partner_personal_options
)

SELECT 
    uds.user_id, 
    uds.partner_id, 
    uds.plan_id, 
    uds.project_id, 
    uds.campaign_id,
    uds.registration_date, 
    uds.confirmation_date, 
    p.type, 
    uds.first_purchase_date, 
    uds.activation_date,
    uds.first_purchase, 
    p.required_first_purchase, 
    SUM(uds.total_purchases / 100) AS total_purchases, 
    p.required_total_purchase, 
    p.fixed_reward, 
    po.po_fixed_reward, 
    p.percentage_reward, 
    po.po_percentage_reward, 

    ROUND(
        COALESCE(SUM(uds.net_revenue), 0) * COALESCE(po.po_percentage_reward, p.percentage_reward, 0) 
        + (COALESCE(po.po_fixed_reward, p.fixed_reward, 0) * 100) / 100, 
    2) AS total_reward,

    ROUND(SUM(uds.partner_revenue / 100), 2) AS partner_revenue,

    ROUND(
        COALESCE(SUM(uds.net_revenue), 0) * COALESCE(po.po_percentage_reward, p.percentage_reward, 0) 
        + (COALESCE(po.po_fixed_reward, p.fixed_reward, 0) * 100) / 100, 
    2) - ROUND(SUM(uds.partner_revenue / 100), 2) AS diff,

    uds.is_duplicate

FROM filtered_user_daily_stats uds

LEFT JOIN filtered_plans p 
    ON uds.plan_id = p.id

LEFT JOIN filtered_partner_personal_options po
    ON uds.plan_id = po.plan_id
    AND uds.partner_id = po.partner_id
    AND (po.start_date IS NULL OR po.start_date <= uds.activation_date)
    AND (po.end_date IS NULL OR po.end_date >= uds.activation_date)

JOIN params pa

GROUP BY 
    uds.campaign_id, 
    user_id, 
    uds.plan_id, 
    uds.project_id, 
    uds.campaign_id

HAVING 
    (
        p.type = 'fixed'
        AND uds.user_id NOT LIKE ("%Test_User")
        AND uds.activation_date IS NOT NULL 
        AND uds.is_duplicate IS NULL
        AND uds.confirmation_date IS NOT NULL
        AND ABS(
            ROUND(COALESCE(po.po_fixed_reward, p.fixed_reward, 0), 2) 
            - ROUND(SUM(uds.partner_revenue / 100), 2)
        ) != 0
    )
    OR 
    (
        p.type LIKE 'mixed%'
        AND uds.user_id NOT LIKE ("%Test_User")
        AND uds.first_purchase IS NOT NULL
        AND uds.activation_date IS NOT NULL
        AND uds.is_duplicate IS NULL
        AND ABS(
            ROUND(
                COALESCE(SUM(uds.net_revenue), 0) * COALESCE(po.po_percentage_reward, p.percentage_reward, 0) 
                + COALESCE(po.po_fixed_reward, p.fixed_reward, 0), 
            2) - ROUND(SUM(uds.partner_revenue / 100), 2)
        ) > 5
    )
    OR 
    (
        p.type = 'fixed_only'
        AND uds.user_id NOT LIKE ("%Test_User")
        AND uds.activation_date IS NOT NULL
        AND uds.is_duplicate IS NULL
        AND ABS(
            ROUND(COALESCE(po.po_fixed_reward, p.fixed_reward, 0), 2) 
            - ROUND(SUM(uds.partner_revenue / 100), 2)
        ) != 0
    )
    OR 
    (
        p.type LIKE 'percentage%'
        AND uds.user_id NOT LIKE ("%Test_User")
        AND uds.activation_date IS NOT NULL
        AND ABS(
            ROUND(
                COALESCE(SUM(uds.net_revenue), 0) * COALESCE(po.po_percentage_reward, p.percentage_reward, 0) 
                + COALESCE(po.po_fixed_reward, p.fixed_reward, 0), 
            2) - ROUND(SUM(uds.partner_revenue / 100), 2)
        ) > 0.1
    )
;
