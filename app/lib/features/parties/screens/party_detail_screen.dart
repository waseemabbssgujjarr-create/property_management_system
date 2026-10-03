import 'package:flutter/material.dart';

class PartyDetailScreen extends StatelessWidget {
  final String partyId;
  const PartyDetailScreen({required this.partyId, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Party Detail')),
      body: Center(child: Text('Party: $partyId')),
    );
  }
}
