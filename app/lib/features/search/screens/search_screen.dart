import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/services/stt_service.dart';
import '../../auth/providers/session_provider.dart';
import '../repositories/search_repository.dart';

/// Global search — voice mic + text.
/// Delegates all DB calls to SearchRepository (no direct Supabase in widget).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _queryCtrl = TextEditingController();
  List<SearchResult> _results = [];
  bool _searching = false;
  bool _listening = false;
  String? _error;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _results = []; _error = null; });
      return;
    }
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    setState(() { _searching = true; _error = null; });
    try {
      final results = await ref.read(searchRepositoryProvider).search(
        dealerId: session.dealerId,
        query: query,
      );
      if (mounted) setState(() { _results = results; _searching = false; });
    } catch (e) {
      if (mounted) setState(() { _searching = false; _error = e.toString(); });
    }
  }

  Future<void> _startVoiceSearch() async {
    final stt = ref.read(sttServiceProvider);
    if (!await stt.init()) return;

    setState(() => _listening = true);
    await stt.startListening(
      onResult: (text, isFinal) {
        _queryCtrl.text = text;
        if (isFinal) {
          setState(() => _listening = false);
          _search(text);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _queryCtrl,
          textDirection: TextDirection.rtl,
          style: AppTypography.urBodyMedium,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'تلاش کریں...',
            hintStyle: AppTypography.urBody.copyWith(color: AppColors.ink300),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: _search,
        ),
        actions: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: AppSpacing.sm),
            child: IconButton(
              onPressed: _listening ? null : _startVoiceSearch,
              icon: Icon(
                _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: _listening ? AppColors.danger : AppColors.brand600,
              ),
            ),
          ),
        ],
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: AppTypography.urBody.copyWith(color: AppColors.danger)))
              : _results.isEmpty
                  ? Center(
                      child: Text(
                        _queryCtrl.text.isEmpty ? 'تلاش شروع کریں' : 'کچھ نہیں ملا',
                        style: AppTypography.urBodyMedium.copyWith(color: AppColors.ink300),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.base),
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _ResultTile(
                        result: _results[i],
                        onTap: () => context.push(_results[i].route),
                      ),
                    ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;
  const _ResultTile({required this.result, required this.onTap});

  IconData get _icon => switch (result.type) {
    'party'    => Icons.person_rounded,
    'property' => Icons.villa_rounded,
    'deal'     => Icons.handshake_rounded,
    _          => Icons.search_rounded,
  };

  Color get _color => switch (result.type) {
    'party'    => AppColors.brand600,
    'property' => AppColors.stageToken,
    'deal'     => AppColors.stageBayana,
    _          => AppColors.ink500,
  };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: _color.withAlpha(20),
        child: Icon(_icon, color: _color, size: 20),
      ),
      title: Text(result.title,
          style: AppTypography.urBodyMedium,
          textDirection: TextDirection.rtl),
      subtitle: result.subtitle.isNotEmpty
          ? Text(result.subtitle, style: AppTypography.caption)
          : null,
      trailing: const Icon(Icons.arrow_back_ios_rounded, size: 14),
    );
  }
}
