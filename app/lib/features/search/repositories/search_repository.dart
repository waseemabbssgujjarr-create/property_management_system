import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/network/supabase_client.dart';

class SearchResult {
  final String type; // 'party' | 'property'
  final String id;
  final String title;
  final String subtitle;
  final String route;

  const SearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}

class SearchRepository {
  final SupabaseClient _client;
  SearchRepository(this._client);

  Future<List<SearchResult>> search({
    required String dealerId,
    required String query,
    int limit = 10,
  }) async {
    if (query.trim().isEmpty) return [];
    try {
      final q = query.trim();

      final results = await Future.wait([
        _searchParties(dealerId, q, limit ~/ 2),
        _searchProperties(dealerId, q, limit ~/ 2),
      ]);

      return [...results[0], ...results[1]];
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<List<SearchResult>> _searchParties(
    String dealerId, String q, int limit) async {
    final data = await _client
        .from('parties')
        .select('id, name, phone, type')
        .eq('dealer_id', dealerId)
        .isFilter('deleted_at', null)
        .or('name.ilike.%$q%,phone.ilike.%$q%')
        .limit(limit);

    return (data as List).map((m) => SearchResult(
      type: 'party',
      id: m['id'] as String,
      title: m['name'] as String? ?? '',
      subtitle: m['phone'] as String? ?? '',
      route: '/parties/${m['id']}',
    )).toList();
  }

  Future<List<SearchResult>> _searchProperties(
    String dealerId, String q, int limit) async {
    final data = await _client
        .from('properties')
        .select('id, society, block, kind, size_marla, status')
        .eq('dealer_id', dealerId)
        .isFilter('deleted_at', null)
        .or('society.ilike.%$q%,block.ilike.%$q%,cert_no.ilike.%$q%')
        .limit(limit);

    return (data as List).map((m) => SearchResult(
      type: 'property',
      id: m['id'] as String,
      title: m['society'] as String? ?? '',
      subtitle: '${m['kind'] ?? ''} • ${m['block'] ?? ''}',
      route: '/inventory/${m['id']}',
    )).toList();
  }
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref.watch(supabaseClientProvider));
});
