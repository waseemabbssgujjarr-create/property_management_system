import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/network/supabase_client.dart';
import '../../../core/platform/file_support.dart';
import '../models/property_models.dart';

class InventoryRepository {
  final SupabaseClient _client;
  InventoryRepository(this._client);

  Future<List<Property>> getProperties({
    required String dealerId,
    PropertyStatus? filterStatus,
    PropertyKind? filterKind,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var query = _client
          .from('properties')
          .select('*, property_photos(url, sort)')
          .eq('dealer_id', dealerId)
          .isFilter('deleted_at', null);

      if (filterStatus != null) {
        query = query.eq('status', filterStatus.dbValue);
      }
      if (filterKind != null) {
        query = query.eq('kind', filterKind.dbValue);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (data as List)
          .map((m) => Property.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<Property> getProperty(String id, String dealerId) async {
    try {
      final data = await _client
          .from('properties')
          .select('*, property_photos(url, sort)')
          .eq('id', id)
          .eq('dealer_id', dealerId)
          .single();
      return Property.fromMap(data);
    } catch (e) {
      throw mapException(e);
    }
  }

  /// Photo-first quick-add: creates property with a photo, fills details later.
  Future<Property> quickAddProperty({
    required String dealerId,
    required PropertyKind kind,
    required String society,
    String? localPhotoPath,
    String? createdBy,
  }) async {
    try {
      final id = const Uuid().v4();

      // Insert property first
      final data = await _client.from('properties').insert({
        'id': id,
        'dealer_id': dealerId,
        'kind': kind.dbValue,
        'society': society,
        'status': 'available',
        'created_by': createdBy,
      }).select().single();

      // Upload photo if provided
      if (localPhotoPath != null) {
        await uploadPropertyPhoto(
          propertyId: id,
          dealerId: dealerId,
          localPath: localPhotoPath,
        );
      }

      return Property.fromMap(data);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<Property> createProperty({
    required String dealerId,
    required Property property,
    List<String> localPhotoPaths = const [],
    String? createdBy,
  }) async {
    try {
      final insertData = property.toInsertMap()
        ..['created_by'] = createdBy;

      final data = await _client
          .from('properties')
          .insert(insertData)
          .select()
          .single();

      final created = Property.fromMap(data);

      // Upload photos
      for (final path in localPhotoPaths) {
        await uploadPropertyPhoto(
          propertyId: created.id,
          dealerId: dealerId,
          localPath: path,
        );
      }

      return created;
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> updateProperty({
    required String id,
    required String dealerId,
    Map<String, dynamic> updates = const {},
  }) async {
    try {
      await _client
          .from('properties')
          .update(updates)
          .eq('id', id)
          .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> updateStatus({
    required String id,
    required String dealerId,
    required PropertyStatus newStatus,
    String? changedBy,
    String? note,
  }) async {
    try {
      // Update property status
      await _client
          .from('properties')
          .update({'status': newStatus.dbValue})
          .eq('id', id)
          .eq('dealer_id', dealerId);

      // Log status change
      await _client.from('property_status_history').insert({
        'property_id': id,
        'dealer_id': dealerId,
        'to_status': newStatus.dbValue,
        'changed_by': changedBy,
        'note': note,
      });
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> softDeleteProperty({
    required String id,
    required String dealerId,
    required String deletedBy,
  }) async {
    try {
      await _client.from('properties').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': deletedBy,
      })
      .eq('id', id)
      .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<String> uploadPropertyPhoto({
    required String propertyId,
    required String dealerId,
    required String localPath,
    int sort = 0,
  }) async {
    if (kIsWeb) throw UnsupportedError('File upload not supported on web');
    try {
      final file = File(localPath);
      final ext = localPath.split('.').last.toLowerCase();
      final fileName = '${const Uuid().v4()}.$ext';
      final storagePath = '$dealerId/$propertyId/$fileName';

      await _client.storage
          .from('property-photos')
          .upload(storagePath, file);

      final url = _client.storage
          .from('property-photos')
          .getPublicUrl(storagePath);

      // Insert photo record
      await _client.from('property_photos').insert({
        'property_id': propertyId,
        'dealer_id': dealerId,
        'url': url,
        'sort': sort,
      });

      return url;
    } catch (e) {
      throw mapException(e);
    }
  }

  /// Duplicate detection: check if a similar property already exists.
  Future<List<Property>> checkDuplicates({
    required String dealerId,
    required String society,
    String? block,
    double? sizeMarla,
    PropertyKind? kind,
  }) async {
    try {
      var query = _client
          .from('properties')
          .select('id, kind, society, block, size_marla, status')
          .eq('dealer_id', dealerId)
          .eq('society', society)
          .isFilter('deleted_at', null)
          .neq('status', 'sold')
          .neq('status', 'withdrawn');

      if (block != null) query = query.eq('block', block);
      if (sizeMarla != null) {
        // Within 10% size range
        query = query
            .gte('size_marla', sizeMarla * 0.9)
            .lte('size_marla', sizeMarla * 1.1);
      }

      final data = await query.limit(5);
      return (data as List)
          .map((m) => Property.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return []; // Non-fatal: return empty on error
    }
  }
}

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(ref.watch(supabaseClientProvider));
});
