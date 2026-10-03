import 'package:flutter/material.dart';

class PropertyDetailScreen extends StatelessWidget {
  final String propertyId;
  const PropertyDetailScreen({required this.propertyId, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Property Detail')),
      body: Center(child: Text('Property: $propertyId')),
    );
  }
}
