import 'package:flutter/material.dart';

class LocationDisclosureScreen extends StatelessWidget {
  final VoidCallback onContinue;
  const LocationDisclosureScreen({Key? key, required this.onContinue}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location Access')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on, size: 48, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'This app records your location in the background — even when the app '
              'is closed — while you are on an active work session, so your employer '
              'can confirm your route and location during that time.\n\n'
              'Location tracking only runs between your START and STOP selfie — it '
              'does not run at any other time.',
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              onPressed: onContinue,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}