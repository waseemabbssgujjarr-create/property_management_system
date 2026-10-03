-- ============================================================
-- MUNSHI — RPC Functions (Dashboard + Aggregates)
-- Version: 1.0 | Date: 2026-10-02
-- ============================================================

-- Expected commission for the current month across open deals
CREATE OR REPLACE FUNCTION get_expected_commission_month(
  p_dealer_id   uuid,
  p_month_start timestamptz
)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(SUM(expected_comm_rs), 0)::bigint
  FROM deals
  WHERE dealer_id = p_dealer_id
    AND stage NOT IN ('closed', 'lost')
    AND deleted_at IS NULL
    AND created_at >= p_month_start;
$$;

-- Monthly P&L summary (used for voice summary and reports)
CREATE OR REPLACE FUNCTION get_monthly_pl(
  p_dealer_id   uuid,
  p_month_start timestamptz,
  p_month_end   timestamptz
)
RETURNS TABLE (
  commission_expected  bigint,
  commission_received  bigint,
  total_expenses       bigint,
  net_pl               bigint,
  deals_closed         int,
  deals_lost           int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    (SELECT COALESCE(SUM(d.expected_comm_rs), 0)
     FROM deals d
     WHERE d.dealer_id = p_dealer_id
       AND d.stage NOT IN ('closed','lost')
       AND d.deleted_at IS NULL
    )::bigint AS commission_expected,

    (SELECT COALESCE(SUM(p.amount_rs), 0)
     FROM payments p
     WHERE p.dealer_id = p_dealer_id
       AND p.kind = 'commission_in'
       AND p.occurred_at >= p_month_start
       AND p.occurred_at < p_month_end
    )::bigint AS commission_received,

    (SELECT COALESCE(SUM(p.amount_rs), 0)
     FROM payments p
     WHERE p.dealer_id = p_dealer_id
       AND p.kind = 'expense'
       AND p.occurred_at >= p_month_start
       AND p.occurred_at < p_month_end
    )::bigint AS total_expenses,

    (
      (SELECT COALESCE(SUM(p.amount_rs), 0)
       FROM payments p
       WHERE p.dealer_id = p_dealer_id
         AND p.kind = 'commission_in'
         AND p.occurred_at >= p_month_start
         AND p.occurred_at < p_month_end)
      -
      (SELECT COALESCE(SUM(p.amount_rs), 0)
       FROM payments p
       WHERE p.dealer_id = p_dealer_id
         AND p.kind = 'expense'
         AND p.occurred_at >= p_month_start
         AND p.occurred_at < p_month_end)
    )::bigint AS net_pl,

    (SELECT COUNT(*)::int
     FROM deals d
     WHERE d.dealer_id = p_dealer_id
       AND d.stage = 'closed'
       AND d.closed_at >= p_month_start
       AND d.closed_at < p_month_end
    ) AS deals_closed,

    (SELECT COUNT(*)::int
     FROM deals d
     WHERE d.dealer_id = p_dealer_id
       AND d.stage = 'lost'
       AND d.updated_at >= p_month_start
       AND d.updated_at < p_month_end
    ) AS deals_lost;
$$;

-- Staff earned vs paid summary (the "moat screen")
CREATE OR REPLACE FUNCTION get_staff_commission_summary(
  p_dealer_id  uuid,
  p_month_start timestamptz,
  p_month_end   timestamptz
)
RETURNS TABLE (
  user_id          uuid,
  user_name        text,
  user_role        text,
  earned_rs        bigint,
  paid_rs_month    bigint,
  pending_rs       bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    u.id                              AS user_id,
    u.name                            AS user_name,
    u.role                            AS user_role,
    COALESCE(SUM(ds.earned_rs), 0)   AS earned_rs,
    (
      SELECT COALESCE(SUM(p.amount_rs), 0)
      FROM payments p
      WHERE p.dealer_id = p_dealer_id
        AND p.paid_to_user_id = u.id
        AND p.kind = 'split_paid'
        AND p.occurred_at >= p_month_start
        AND p.occurred_at < p_month_end
    )                                  AS paid_rs_month,
    COALESCE(SUM(ds.earned_rs), 0) - COALESCE(SUM(ds.paid_rs), 0) AS pending_rs
  FROM users u
  LEFT JOIN deal_splits ds ON ds.user_id = u.id AND ds.dealer_id = p_dealer_id AND ds.deleted_at IS NULL
  WHERE u.dealer_id = p_dealer_id
    AND u.active = true
    AND u.role != 'owner'
  GROUP BY u.id, u.name, u.role;
$$;

-- Demand matching score (returns top matches for a buyer requirement)
CREATE OR REPLACE FUNCTION match_buyer_to_inventory(
  p_dealer_id     uuid,
  p_requirement_id uuid
)
RETURNS TABLE (
  property_id   uuid,
  match_score   numeric,
  society       text,
  block         text,
  size_marla    numeric,
  demand_rs     bigint,
  status        text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH req AS (
    SELECT * FROM requirements WHERE id = p_requirement_id AND dealer_id = p_dealer_id
  )
  SELECT
    pr.id          AS property_id,
    (
      -- Score components: budget match (0.5) + area match (0.3) + kind match (0.2)
      CASE WHEN pr.demand_rs BETWEEN (SELECT budget_min_rs FROM req) AND (SELECT budget_max_rs FROM req)
           THEN 0.5 ELSE 0 END
      +
      CASE WHEN pr.society = ANY((SELECT areas FROM req)::text[]) THEN 0.3 ELSE 0 END
      +
      CASE WHEN pr.kind = ANY((SELECT kinds FROM req)::text[]) THEN 0.2 ELSE 0 END
    )              AS match_score,
    pr.society,
    pr.block,
    pr.size_marla,
    pr.demand_rs,
    pr.status
  FROM properties pr
  WHERE pr.dealer_id = p_dealer_id
    AND pr.status = 'available'
    AND pr.deleted_at IS NULL
  ORDER BY match_score DESC
  LIMIT 10;
$$;
