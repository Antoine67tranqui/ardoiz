import 'package:ardoiz/core/brand.dart';
import 'package:ardoiz/ui/widgets/auth_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('le logo ne change pas sans qu\'on le décide (image de référence)', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: RepaintBoundary(key: Key('logo'), child: BrandMark(size: 256))),
    ));
    await expectLater(find.byKey(const Key('logo')), matchesGoldenFile('../goldens/logo.png'));
  });

  test('le nom et l\'accroche de la marque', () {
    expect(Brand.name, 'Carné');
    expect(Brand.tagline, isNotEmpty);
  });
}
