import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/mono.dart';
import '../ui/motion.dart';

/// Yönetim panellerinin ortak parçaları.

const panelApi = 'api/v1/panels';

int pi(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double pd(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String ps(Object? v) => v == null ? '' : '$v';

String pDate(String? iso, {bool time = true}) {
  final t = DateTime.tryParse(iso ?? '')?.toLocal();
  if (t == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year}${time ? ' ${two(t.hour)}:${two(t.minute)}' : ''}';
}

void pToast(BuildContext context, String m) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m)));

Future<bool> pConfirm(BuildContext context, String title, String text, {String ok = 'Sil', bool destructive = true}) async =>
    await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          CupertinoDialogAction(isDestructiveAction: destructive, isDefaultAction: !destructive, onPressed: () => Navigator.of(ctx).pop(true), child: Text(ok)),
        ],
      ),
    ) ??
    false;

/// Başlık + (isteğe bağlı) sekmeler + gövde.
class PanelPage extends StatelessWidget {
  const PanelPage({super.key, required this.title, required this.body, this.fab, this.actions = const [], this.tabs, this.tab = 0, this.onTab});
  final String title;
  final Widget body;
  final Widget? fab;
  final List<Widget> actions;
  final List<String>? tabs;
  final int tab;
  final ValueChanged<int>? onTab;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        floatingActionButton: fab,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: c.ink)),
                    Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(19, weight: FontWeight.w800))),
                    ...actions,
                  ],
                ),
              ),
              if (tabs != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(13), border: Border.all(color: c.line)),
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs!.length; i++)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => onTab?.call(i),
                            child: AnimatedContainer(
                              duration: Motion.of(context, Motion.fast),
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: tab == i ? c.ink : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(tabs![i], style: c.text(12.5, weight: FontWeight.w700, color: tab == i ? c.bg : c.ink)),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

Widget panelFab(ArconMono c, String label, VoidCallback onTap) => FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: c.ink,
      foregroundColor: c.bg,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.add_rounded),
      label: Text(label, style: c.text(14, weight: FontWeight.w700, color: c.bg)),
    );

Widget panelField(ArconMono c, TextEditingController ctl, String hint, {IconData? icon, int lines = 1, TextInputType? type, ValueChanged<String>? onChanged, String? label}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: c.label(label)),
          TextField(
            controller: ctl,
            keyboardType: type ?? (lines > 1 ? TextInputType.multiline : null),
            minLines: lines,
            maxLines: lines > 1 ? lines + 8 : 1,
            onChanged: onChanged,
            textCapitalization: TextCapitalization.sentences,
            keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
            style: c.text(15, height: lines > 1 ? 1.45 : null),
            cursorColor: c.ink,
            decoration: c.input(hint, lines > 1 ? null : icon),
          ),
        ],
      ),
    );

Widget panelChips<T>(ArconMono c, List<(T, String)> items, T value, ValueChanged<T> onChanged) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (v, label) in items)
          GestureDetector(
            onTap: () => onChanged(v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: v == value ? c.ink : c.bg,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: v == value ? c.ink : c.line),
              ),
              child: Text(label, style: c.text(12.5, weight: FontWeight.w700, color: v == value ? c.bg : c.ink)),
            ),
          ),
      ],
    );

Widget panelTag(ArconMono c, String label, {bool strong = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: strong ? c.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: strong ? c.ink : c.line),
      ),
      child: Text(label, style: c.text(10.5, weight: FontWeight.w700, color: strong ? c.bg : c.muted)),
    );

Widget panelSwitch(ArconMono c, String label, bool value, ValueChanged<bool> onChanged, {String? hint}) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: c.text(14, weight: FontWeight.w600)),
                if (hint != null) Text(hint, style: c.text(11.5, color: c.muted)),
              ],
            ),
          ),
          Switch.adaptive(value: value, activeTrackColor: c.ink, onChanged: onChanged),
        ],
      ),
    );

Widget panelSection(ArconMono c, String title) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        children: [
          Text(trUpper(title), style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: c.line)),
        ],
      ),
    );

/// Kart görünümlü satır.
Widget panelCard(ArconMono c, {required Widget child, VoidCallback? onTap, EdgeInsets padding = const EdgeInsets.all(14)}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
        child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
