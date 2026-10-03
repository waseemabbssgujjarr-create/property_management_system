import 'package:flutter_test/flutter_test.dart';
import 'package:munshi/core/services/permission_service.dart';
import 'package:munshi/features/auth/models/auth_models.dart';

AppSession makeSession({required String role}) => AppSession(
  userId: 'user-1',
  dealerId: 'dealer-1',
  phone: '+923001234567',
  name: 'Test User',
  role: role,
);

void main() {
  group('PermissionService — owner', () {
    late PermissionService svc;
    setUp(() => svc = PermissionService(makeSession(role: 'owner')));

    test('owner can do everything', () {
      for (final perm in Permission.values) {
        expect(svc.can(perm), isTrue,
            reason: 'Owner should have permission: $perm');
      }
    });
  });

  group('PermissionService — munshi', () {
    late PermissionService svc;
    setUp(() => svc = PermissionService(makeSession(role: 'munshi')));

    test('munshi can create deals', () {
      expect(svc.can(Permission.createDeal), isTrue);
    });

    test('munshi can record payments', () {
      expect(svc.can(Permission.recordPayment), isTrue);
    });

    test('munshi cannot view subscription', () {
      expect(svc.can(Permission.viewSubscription), isFalse);
    });

    test('munshi cannot change staff role', () {
      expect(svc.can(Permission.changeStaffRole), isFalse);
    });

    test('munshi cannot delete deals', () {
      expect(svc.can(Permission.deleteDeal), isFalse);
    });

    test('munshi cannot view all payments', () {
      expect(svc.can(Permission.viewAllPayments), isFalse);
    });
  });

  group('PermissionService — agent', () {
    late PermissionService svc;
    setUp(() => svc = PermissionService(makeSession(role: 'agent')));

    test('agent can create deals', () {
      expect(svc.can(Permission.createDeal), isTrue);
    });

    test('agent can view own commission', () {
      expect(svc.can(Permission.viewOwnCommission), isTrue);
    });

    test('agent cannot pay staff', () {
      expect(svc.can(Permission.payStaff), isFalse);
    });

    test('agent cannot view CNIC', () {
      expect(svc.can(Permission.viewCnic), isFalse);
    });

    test('agent cannot view subscription', () {
      expect(svc.can(Permission.viewSubscription), isFalse);
    });

    test('agent cannot edit commission percentage', () {
      expect(svc.can(Permission.editCommissionPct), isFalse);
    });
  });

  group('PermissionService — manager', () {
    late PermissionService svc;
    setUp(() => svc = PermissionService(makeSession(role: 'manager')));

    test('manager can advance deal stage', () {
      expect(svc.can(Permission.advanceDealStage), isTrue);
    });

    test('manager can invite staff', () {
      expect(svc.can(Permission.inviteStaff), isTrue);
    });

    test('manager cannot change staff role', () {
      // Role changes are owner-only
      expect(svc.can(Permission.changeStaffRole), isFalse);
    });

    test('manager cannot view subscription', () {
      expect(svc.can(Permission.viewSubscription), isFalse);
    });
  });

  group('PermissionService — unauthenticated', () {
    late PermissionService svc;
    setUp(() => svc = const PermissionService(null));

    test('null session: no permissions', () {
      for (final perm in Permission.values) {
        expect(svc.can(perm), isFalse,
            reason: 'Unauthenticated should not have: $perm');
      }
    });
  });
}
