import 'package:flutter/material.dart';

class IncidentDetailsPage extends StatelessWidget {
  final Map<String, dynamic> incidentData;

  const IncidentDetailsPage({Key? key, required this.incidentData}) : super(key: key);

  String _valueOf(String key, [String fallback = '']) {
    final v = incidentData[key];
    return v == null ? fallback : v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final incidentType = _valueOf('incidentType', 'Incident');
    final locationText = _valueOf('locationText', 'Unknown Location');
    final timestamp = _valueOf('timestamp');
    final department = _valueOf('department').toUpperCase();
    final incidentId = _valueOf('incidentId');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident Details'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🚨 $incidentType', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Department: $department'),
            const SizedBox(height: 8),
            Text('Location: $locationText'),
            const SizedBox(height: 8),
            if (timestamp.isNotEmpty) Text('Reported: $timestamp'),
            const SizedBox(height: 12),
            if (incidentId.isNotEmpty)
              SelectableText('Incident ID: $incidentId',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
          ],
        ),
      ),
    );
  }
}



