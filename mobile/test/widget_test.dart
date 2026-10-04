import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('shows server settings and live session controls', (
    tester,
  ) async {
    await tester.pumpWidget(const LiveDemoApp());

    expect(find.text('Kiểm tra kết nối thật'), findsOneWidget);
    expect(find.text('IP / hostname'), findsOneWidget);
    expect(find.text('Bắt đầu'), findsOneWidget);
    expect(find.text('Thử video event'), findsOneWidget);
    expect(find.text('Thử audio event'), findsOneWidget);
  });
}
