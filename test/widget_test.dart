import 'package:flutter_test/flutter_test.dart';
import 'package:sumnvault/main.dart';

void main() {
  testWidgets('renders the vault library', (tester) async {
    await tester.pumpWidget(const SumnVaultApp());

    expect(find.text('Your private digital vaults'), findsOneWidget);
    expect(find.text('Personal.svault'), findsOneWidget);
    expect(find.text('Documents.svault'), findsOneWidget);
  });
}
