import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/session_provider.dart';
import '../models/property_models.dart';
import '../repositories/inventory_repository.dart';

/// Inventory list with optional filters.
class InventoryNotifier extends AsyncNotifier<List<Property>> {
  PropertyStatus? _filterStatus;
  PropertyKind? _filterKind;
  String? _searchQuery;

  @override
  Future<List<Property>> build() async {
    final session = ref.watch(currentSessionProvider);
    if (session == null) return [];
    return ref.read(inventoryRepositoryProvider).getProperties(
      dealerId: session.dealerId,
      filterStatus: _filterStatus,
      filterKind: _filterKind,
      searchQuery: _searchQuery,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  void setFilter({PropertyStatus? status, PropertyKind? kind, String? query}) {
    _filterStatus = status;
    _filterKind = kind;
    _searchQuery = query;
    ref.invalidateSelf();
  }

  Future<Property?> createProperty(Property property, List<String> photoPaths) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return null;
    final created = await ref.read(inventoryRepositoryProvider).createProperty(
      dealerId: session.dealerId,
      property: property,
      localPhotoPaths: photoPaths,
      createdBy: session.userId,
    );
    ref.invalidateSelf();
    return created;
  }
}

final inventoryProvider =
    AsyncNotifierProvider<InventoryNotifier, List<Property>>(
  InventoryNotifier.new,
);

/// Single property detail
final propertyDetailProvider =
    FutureProvider.family<Property, String>((ref, propertyId) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) throw Exception('Not authenticated');
  return ref
      .read(inventoryRepositoryProvider)
      .getProperty(propertyId, session.dealerId);
});
