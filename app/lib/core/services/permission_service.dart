import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/models/auth_models.dart';
import '../../features/auth/providers/session_provider.dart';

/// Permission enum — all capabilities in the app.
/// Checked at UI layer AND service/repo layer.
enum Permission {
  // Deals
  listAllDeals,
  viewDealDetail,
  createDeal,
  advanceDealStage,
  markDealLost,
  editDealPrice,
  editCommissionPct,
  deleteDeal,

  // Money
  viewAllPayments,
  viewOwnCommission,
  recordPayment,
  payStaffCommission,
  reversePayment,
  viewStaffSplits,
  editStaffSplits,
  exportFinancials,

  // Inventory
  viewInventory,
  createProperty,
  editProperty,
  changePropertyStatus,
  deleteProperty,
  importProperties,

  // Parties
  viewParties,
  createParty,
  editParty,
  viewCnic,
  deleteParty,
  manageWaOptIn,

  // Staff
  viewStaff,
  inviteStaff,
  changeStaffRole,
  deactivateStaff,
  viewStaffCommission,
  payStaff,

  // Documents
  viewDocuments,
  uploadDocuments,

  // Platform
  viewSubscription,
  changePlan,
  manageWhatsApp,
  viewAuditLog,
  exportData,
  changeMode,
  changeLanguage,
}

/// Permission service — evaluates role-based permissions.
///
/// Three-layer enforcement:
/// 1. This service (UI + service layer checks)
/// 2. Supabase RLS (database layer — cannot be bypassed)
class PermissionService {
  final AppSession? session;

  const PermissionService(this.session);

  bool can(Permission permission) {
    if (session == null) return false;
    return _evaluate(session!.role, permission);
  }

  bool cannot(Permission permission) => !can(permission);

  bool _evaluate(String role, Permission permission) {
    return switch (permission) {
      // Owner can do everything
      _ when role == 'owner' => true,

      // Manager permissions
      Permission.listAllDeals       => true,
      Permission.viewDealDetail     => true,
      Permission.createDeal         => true,
      Permission.advanceDealStage   when role == 'manager' => true,
      Permission.markDealLost       when role == 'manager' => true,
      Permission.editDealPrice      when role == 'manager' => true,
      Permission.editCommissionPct  when role == 'manager' => true,
      Permission.deleteDeal         when role == 'manager' => true,
      Permission.viewAllPayments    when role == 'manager' => true,
      Permission.recordPayment      when role == 'manager' => true,
      Permission.reversePayment     when role == 'manager' => true,
      Permission.viewStaffSplits    when role == 'manager' => true,
      Permission.editStaffSplits    when role == 'manager' => true,
      Permission.exportFinancials   when role == 'manager' => true,
      Permission.viewInventory      when role == 'manager' => true,
      Permission.createProperty     when role == 'manager' => true,
      Permission.editProperty       when role == 'manager' => true,
      Permission.changePropertyStatus when role == 'manager' => true,
      Permission.deleteProperty     when role == 'manager' => true,
      Permission.importProperties   when role == 'manager' => true,
      Permission.viewParties        when role == 'manager' => true,
      Permission.createParty        when role == 'manager' => true,
      Permission.editParty          when role == 'manager' => true,
      Permission.viewCnic           when role == 'manager' => true,
      Permission.deleteParty        when role == 'manager' => true,
      Permission.manageWaOptIn      when role == 'manager' => true,
      Permission.viewStaff          when role == 'manager' => true,
      Permission.inviteStaff        when role == 'manager' => true,
      Permission.viewStaffCommission when role == 'manager' => true,
      Permission.viewDocuments      when role == 'manager' => true,
      Permission.uploadDocuments    when role == 'manager' => true,
      Permission.exportData         when role == 'manager' => true,
      Permission.changeMode         when role == 'manager' => true,
      Permission.changeLanguage     when role == 'manager' => true,

      // Agent permissions
      Permission.listAllDeals       when role == 'agent' => true, // filtered server-side
      Permission.createDeal         when role == 'agent' => true,
      Permission.viewInventory      when role == 'agent' => true,
      Permission.createProperty     when role == 'agent' => true,
      Permission.viewParties        when role == 'agent' => true,
      Permission.createParty        when role == 'agent' => true,
      Permission.editParty          when role == 'agent' => true,
      Permission.manageWaOptIn      when role == 'agent' => true,
      Permission.viewOwnCommission  when role == 'agent' => true,
      Permission.changeMode         when role == 'agent' => true,
      Permission.changeLanguage     when role == 'agent' => true,

      // Munshi permissions
      Permission.listAllDeals       when role == 'munshi' => true,
      Permission.viewDealDetail     when role == 'munshi' => true,
      Permission.createDeal         when role == 'munshi' => true,
      Permission.viewInventory      when role == 'munshi' => true,
      Permission.createProperty     when role == 'munshi' => true,
      Permission.editProperty       when role == 'munshi' => true,
      Permission.viewParties        when role == 'munshi' => true,
      Permission.createParty        when role == 'munshi' => true,
      Permission.editParty          when role == 'munshi' => true,
      Permission.manageWaOptIn      when role == 'munshi' => true,
      Permission.recordPayment      when role == 'munshi' => true,
      Permission.viewDocuments      when role == 'munshi' => true,
      Permission.uploadDocuments    when role == 'munshi' => true,
      Permission.changeMode         when role == 'munshi' => true,
      Permission.changeLanguage     when role == 'munshi' => true,

      _ => false,
    };
  }
}

final permissionServiceProvider = Provider<PermissionService>((ref) {
  final session = ref.watch(currentSessionProvider);
  return PermissionService(session);
});

/// Widget guard — shows [child] if permission granted, [fallback] otherwise.
/// Use this to hide UI elements the user cannot access.
