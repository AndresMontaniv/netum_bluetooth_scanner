import 'package:flutter/material.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NETUM scanner example',
      home: Scaffold(
        appBar: AppBar(title: const Text('NETUM scanner example')),
        body: const Center(child: Text('No plugin API yet.')),
      ),
    );
  }
}
