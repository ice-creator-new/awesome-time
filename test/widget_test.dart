import 'package:awesome_time/main.dart';
import 'package:awesome_time/ui/waveform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows connection page', (tester) async {
    await tester.pumpWidget(const AwesomeTimeApp());
    expect(find.text('连接电脑桥接'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
    expect(find.text('演示模式（无需电脑）'), findsOneWidget);
  });

  testWidgets('demo mode opens now playing with artwork title', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AwesomeTimeApp());
    await tester.tap(find.text('演示模式（无需电脑）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('夜空中最亮的星'), findsOneWidget);
    expect(find.textContaining('逃跑计划'), findsOneWidget);
    expect(find.text('正在播放'), findsNothing);
    expect(find.byType(Waveform), findsNothing);
  });

  testWidgets('landscape splits controls and waveform', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AwesomeTimeApp());
    await tester.tap(find.text('演示模式（无需电脑）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('夜空中最亮的星'), findsOneWidget);
    expect(find.byType(Waveform), findsOneWidget);
  });
}
