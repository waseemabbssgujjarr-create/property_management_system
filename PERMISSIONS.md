# PERMISSIONS — Munshi
**Version:** 1.0 | **Date:** 2026-10-02

---

## 1. Design Principle

Permissions are enforced at three layers:
1. **UI** — hide/disable elements the user cannot use
2. **Service layer** — reject calls from unauthorized roles before hitting the DB
3. **Database RLS** — final enforcement, cannot be bypassed by client

Never rely on UI alone. A dealer modifying the app client should not gain data access.

---

## 2. Permission Matrix

### Deals

| Action | owner | manager | agent | munshi |
|---|---|---|---|---|
| list_all_deals | ✅ | ✅ | own/assigned | ✅ |
| view_deal_detail | ✅ | ✅ | own/assigned | ✅ |
| create_deal | ✅ | ✅ | ✅ | ✅ |
| advance_stage | ✅ | ✅ | own/assigned | ❌ |
| mark_lost | ✅ | ✅ | own/assigned | ❌ |
| edit_deal_price | ✅ | ✅ | ❌ | ❌ |
| edit_commission_pct | ✅ | ✅ | ❌ | ❌ |
| delete_deal | ✅ | ✅ | ❌ | ❌ |

### Money

| Action | owner | manager | agent | munshi |
|---|---|---|---|---|
| view_all_payments | ✅ | configurable | ❌ | configurable |
| view_own_commission | ✅ | ✅ | ✅ | N/A |
| record_token_payment | ✅ | ✅ | ❌ | ✅ |
| record_bayana_payment | ✅ | ✅ | ❌ | ✅ |
| record_commission_in | ✅ | ✅ | ❌ | ✅ |
| pay_staff_commission | ✅ | configurable | ❌ | ❌ |
| reverse_payment | ✅ | ✅ | ❌ | ❌ |
| view_staff_commission_splits | ✅ | ✅ | own only | ❌ |
| edit_staff_splits | ✅ | ✅ | ❌ | ❌ |
| export_financial_report | ✅ | ✅ | ❌ | ❌ |

### Inventory

| Action | owner | manager | agent | munshi |
|---|---|---|---|---|
| view_all_properties | ✅ | ✅ | ✅ | ✅ |
| create_property | ✅ | ✅ | ✅ | ✅ |
| edit_property | ✅ | ✅ | assigned | ✅ |
| change_property_status | ✅ | ✅ | assigned | ❌ |
| delete_property | ✅ | ✅ | ❌ | ❌ |
| import_properties | ✅ | ✅ | ❌ | ❌ |

### Parties

| Action | owner | manager | agent | munshi |
|---|---|---|---|---|
| view_all_parties | ✅ | ✅ | ✅ | ✅ |
| create_party | ✅ | ✅ | ✅ | ✅ |
| edit_party | ✅ | ✅ | ✅ | ✅ |
| view_cnic | ✅ | ✅ | ❌ | ❌ |
| delete_party | ✅ | ✅ | ❌ | ❌ |
| manage_wa_opt_in | ✅ | ✅ | ✅ | ✅ |

### Staff

| Action | owner | manager | agent | munshi |
|---|---|---|---|---|
| view_staff_list | ✅ | ✅ | ❌ | ❌ |
| invite_staff | ✅ | ✅ | ❌ | ❌ |
| change_staff_role | ✅ | ❌ | ❌ | ❌ |
| deactivate_staff | ✅ | ❌ | ❌ | ❌ |
| view_staff_commission | ✅ | ✅ | own | ❌ |
| pay_staff | ✅ | configurable | ❌ | ❌ |

### Settings / Platform

| Action | owner | manager | agent | munshi |
|---|---|---|---|---|
| view_subscription | ✅ | ❌ | ❌ | ❌ |
| change_plan | ✅ | ❌ | ❌ | ❌ |
| manage_whatsapp | ✅ | configurable | ❌ | ❌ |
| view_audit_log | ✅ | ❌ | ❌ | ❌ |
| export_data | ✅ | ✅ | ❌ | ❌ |
| change_simple_detail_mode | ✅ | ✅ | ✅ | ✅ |
| change_language | ✅ | ✅ | ✅ | ✅ |

---

## 3. Implementation

### 3.1 Flutter Permission Service

```dart
// lib/core/services/permission_service.dart
class PermissionService {
  final AppUser currentUser;

  bool can(Permission permission, {String? resourceOwnerId}) {
    return _evaluate(currentUser.role, permission, resourceOwnerId);
  }

  bool cannot(Permission permission, {String? resourceOwnerId}) => !can(permission);
}

enum Permission {
  // Deals
  listAllDeals, viewDealDetail, createDeal, advanceDealStage, markDealLost,
  editDealPrice, editCommissionPct, deleteDeal,
  // Money
  viewAllPayments, recordPayment, payStaffCommission, reversePayment,
  viewStaffSplits, editStaffSplits, exportFinancials,
  // Inventory
  viewInventory, createProperty, editProperty, deleteProperty, importProperties,
  // Parties
  viewParties, createParty, editParty, viewCnic, deleteParty,
  // Staff
  viewStaff, inviteStaff, changeStaffRole, deactivateStaff, viewStaffCommission,
  // Platform
  viewSubscription, changePlan, manageWhatsApp, viewAuditLog, exportData,
}
```

### 3.2 Usage in UI

```dart
// Hide elements user cannot access
if (permissionService.can(Permission.editCommissionPct))
  CommissionEditButton(...)

// Or use the PermissionGuard widget
PermissionGuard(
  permission: Permission.payStaffCommission,
  child: PayStaffButton(...),
  fallback: SizedBox.shrink(),
)
```

### 3.3 RLS Policy Examples

```sql
-- Agents can only see their assigned deals
CREATE POLICY "agent_deals" ON deals FOR SELECT
USING (
  dealer_id = (auth.jwt() ->> 'dealer_id')::uuid AND (
    (auth.jwt() ->> 'role') IN ('owner', 'manager', 'munshi')
    OR assigned_agent_id = (auth.jwt() ->> 'user_id')::uuid
  )
);

-- Only owner can see subscription
CREATE POLICY "owner_subscription" ON subscriptions FOR SELECT
USING (
  dealer_id = (auth.jwt() ->> 'dealer_id')::uuid AND
  (auth.jwt() ->> 'role') = 'owner'
);

-- Financial records: insert allowed, never update/delete
CREATE POLICY "payments_insert" ON payments FOR INSERT
WITH CHECK (dealer_id = (auth.jwt() ->> 'dealer_id')::uuid);
-- No UPDATE or DELETE policy exists → impossible to update a payment
```

---

## 4. Configurable Permissions (Future)

Some permissions are marked "configurable" for manager role. This will be a settings screen where the owner can toggle manager-level access per category. In MVP, use the defaults above. The data model supports this as a `permission_overrides` table keyed by `(dealer_id, user_id, permission_key, granted bool)`.
