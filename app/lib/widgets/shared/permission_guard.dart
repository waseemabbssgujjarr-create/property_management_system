import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/permission_service.dart';

/// Conditionally renders [child] if the current user has [permission].
/// Shows [fallback] (default: nothing) otherwise.
class PermissionGuard extends ConsumerWidget {
  final Permission permission;
  final Widget child;
  final Widget fallback;

  const PermissionGuard({
    required this.permission,
    required this.child,
    this.fallback = const SizedBox.shrink(),
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionServiceProvider);
    return perms.can(permission) ? child : fallback;
  }
}
