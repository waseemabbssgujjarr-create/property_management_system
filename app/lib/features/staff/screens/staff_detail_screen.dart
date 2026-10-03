import 'package:flutter/material.dart';

class StaffDetailScreen extends StatelessWidget {
  final String staffId;
  const StaffDetailScreen({required this.staffId, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff Detail')),
      body: Center(child: Text('Staff: $staffId')),
    );
  }
}
