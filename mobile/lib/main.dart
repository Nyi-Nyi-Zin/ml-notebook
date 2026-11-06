import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'workspace.dart';

const ink = Color(0xFF0D1219),
    panel = Color(0xFF151D28),
    edge = Color(0xFF2C3849),
    lime = Color(0xFFB7ED7D),
    muted = Color(0xFF98A8BC),
    blue = Color(0xFF8CCEF5),
    red = Color(0xFFEDA5A1);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DraftRoomApp(workspace: Workspace()));
}

class DraftRoomApp extends StatefulWidget {
  final Workspace workspace;
  final bool initialize;
  const DraftRoomApp({
    super.key,
    required this.workspace,
    this.initialize = true,
  });
  @override
  State<DraftRoomApp> createState() => _DraftRoomAppState();
}

class _DraftRoomAppState extends State<DraftRoomApp> {
  @override
  void initState() {
    super.initState();
    if (widget.initialize) unawaited(widget.workspace.init());
  }

  @override
  void dispose() {
    widget.workspace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DraftRoom · MLBB Coach',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: lime,
        brightness: Brightness.dark,
      ).copyWith(primary: lime, surface: panel, onPrimary: ink),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: const Color(0xFFEAF0F8),
        displayColor: const Color(0xFFEAF0F8),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ink,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: edge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: edge),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: edge),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerTheme: const DividerThemeData(color: edge, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    ),
    home: AnimatedBuilder(
      animation: widget.workspace,
      builder: (context, _) => Desk(workspace: widget.workspace),
    ),
  );
}

class Desk extends StatefulWidget {
  final Workspace workspace;
  const Desk({super.key, required this.workspace});
  @override
  State<Desk> createState() => _DeskState();
}

class _DeskState extends State<Desk> {
  Workspace get w => widget.workspace;
  int page = 0, coachTab = 0;
  bool working = false;
  final titleController = TextEditingController(),
      notesController = TextEditingController(),
      urlController = TextEditingController();
  final titleFocus = FocusNode(),
      notesFocus = FocusNode(),
      urlFocus = FocusNode();
  @override
  void dispose() {
    for (final c in [titleController, notesController, urlController]) {
      c.dispose();
    }
    for (final f in [titleFocus, notesFocus, urlFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  void message(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> run(Future<void> Function() action, {String? success}) async {
    if (working) return;
    setState(() => working = true);
    try {
      await action();
      if (success != null) message(success);
    } catch (e) {
      message(e is FormatException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<bool> confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep working'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;
  void syncFields() {
    if (!titleFocus.hasFocus && titleController.text != w.draft!.title) {
      titleController.text = w.draft!.title;
    }
    if (!notesFocus.hasFocus && notesController.text != w.draft!.notes) {
      notesController.text = w.draft!.notes;
    }
    if (!urlFocus.hasFocus && urlController.text != w.api.baseUrl) {
      urlController.text = w.api.baseUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (w.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (w.catalog == null || w.draft == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Text(w.error ?? 'Workspace could not start.'),
          ),
        ),
      );
    }
    syncFields();
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: 'Draft',
      ),
      const NavigationDestination(
        icon: Icon(Icons.route_outlined),
        label: 'Playbook',
      ),
      const NavigationDestination(icon: Icon(Icons.history), label: 'Sessions'),
      const NavigationDestination(
        icon: Icon(Icons.groups_outlined),
        label: 'Team',
      ),
      const NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 31,
              height: 31,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: lime.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: lime.withValues(alpha: .4)),
              ),
              child: const Text(
                'DR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: lime,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'DraftRoom',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
          ],
        ),
        actions: [
          if (wide)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: edge),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                w.online ? 'Rust API connected' : 'Offline practice',
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ),
          IconButton(
            tooltip: 'Switch advice language',
            onPressed: () => unawaited(w.toggleLanguage()),
            icon: Text(
              w.language == 'en' ? 'EN' : 'မြန်မာ',
              style: const TextStyle(fontSize: 12, color: lime),
            ),
          ),
          IconButton(
            tooltip: w.user == null ? 'Sign in' : 'Account settings',
            onPressed: () =>
                w.user == null ? authDialog() : setState(() => page = 4),
            icon: Icon(
              w.user == null
                  ? Icons.account_circle_outlined
                  : Icons.verified_user_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            NavigationRail(
              backgroundColor: ink,
              labelType: NavigationRailLabelType.all,
              selectedIndex: page,
              onDestinationSelected: (i) => setState(() => page = i),
              destinations: destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
          Expanded(
            child: Column(
              children: [
                if (working || w.busy)
                  const LinearProgressIndicator(minHeight: 2),
                if (w.error != null)
                  Container(
                    color: const Color(0xFF342D1F),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            w.error!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dismiss notice',
                          onPressed: () => setState(() => w.error = null),
                          icon: const Icon(Icons.close, size: 17),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(wide ? 28 : 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1400),
                        child: switch (page) {
                          0 => draftPage(),
                          1 => playbookPage(),
                          2 => sessionsPage(),
                          3 => teamPage(),
                          _ => settingsPage(),
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (i) => setState(() => page = i),
              destinations: destinations,
              height: 70,
            ),
    );
  }

  Widget heading(
    String eyebrow,
    String title,
    String subtitle, {
    Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: LayoutBuilder(
      builder: (c, size) {
        final texts = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                color: lime,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              title,
              style: TextStyle(
                fontSize: size.maxWidth < 500 ? 29 : 36,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: muted, fontSize: 13, height: 1.6),
            ),
          ],
        );
        return size.maxWidth > 700
            ? Row(
                children: [
                  Expanded(child: texts),
                  ?trailing,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  texts,
                  if (trailing != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: trailing,
                    ),
                ],
              );
      },
    ),
  );
  Widget box(Widget child, {EdgeInsets padding = const EdgeInsets.all(20)}) =>
      Card(
        margin: EdgeInsets.zero,
        child: Padding(padding: padding, child: child),
      );
  Widget sectionTitle(String title, {Widget? trailing}) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      ?trailing,
    ],
  );
  Widget pill(String label, {Color color = muted}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      border: Border.all(color: color.withValues(alpha: .25)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label, style: TextStyle(fontSize: 10, color: color)),
  );
  Widget gap([double h = 16]) => SizedBox(height: h);
  Widget draftPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'PREPARE. ADAPT. COMMIT.',
        'Your next winning draft.',
        'Build the lineup. Understand the trade-offs. Give your team a clear plan.',
        trailing: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: working
                  ? null
                  : () async {
                      if (w.dirty &&
                          !await confirm(
                            'Start a new draft?',
                            'Your current changes remain only in the local cache until you save them.',
                          )) {
                        return;
                      }
                      w.newDraft();
                    },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New draft'),
            ),
            FilledButton.icon(
              onPressed: working ? null : save,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('Save draft'),
            ),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          pill(
            w.current == null
                ? 'PRACTICE DRAFT'
                : 'CLOUD · REV ${w.current!.revision}',
            color: blue,
          ),
          pill(
            w.dirty ? 'Unsaved edits' : 'Saved state',
            color: w.dirty ? Colors.amber : muted,
          ),
          pill('Free draft · manual ban order'),
          if (!w.canEdit)
            pill(
              w.current?.archived == true
                  ? 'ARCHIVED · READ ONLY'
                  : 'VIEWER · READ ONLY',
              color: red,
            ),
        ],
      ),
      gap(),
      LayoutBuilder(
        builder: (c, size) {
          final board = Column(children: [draftBoard(), gap(), notes()]);
          final coach = coachPanel();
          return size.maxWidth >= 1050
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: board),
                    const SizedBox(width: 22),
                    Expanded(flex: 4, child: coach),
                  ],
                )
              : Column(children: [board, gap(), coach]);
        },
      ),
      gap(),
      const Text(
        'Independent coaching workspace · not affiliated with MOONTON. Suggestions are heuristics, not live win-rate or patch verification.',
        style: TextStyle(color: muted, fontSize: 11, height: 1.7),
      ),
    ],
  );
  Widget draftBoard() => box(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle(
          'Draft board / 5v5',
          trailing: PopupMenuButton<String>(
            tooltip: 'Draft actions',
            onSelected: (value) async {
              if (value == 'swap') w.swap();
              if (value == 'undo') w.undo();
              if (value == 'copy') {
                await copyText(w.exportJson(), 'Draft JSON copied.');
              }
              if (value == 'import') await importDialog();
              if (value == 'example') {
                if (w.dirty &&
                    !await confirm(
                      'Load example?',
                      'This replaces the working lineup. Save or copy it first if needed.',
                    )) {
                  return;
                }
                w.newDraft(example: true);
              }
              if (value == 'brief') {
                await copyText(w.brief(), 'Coaching brief copied.');
              }
            },
            itemBuilder: (c) => [
              const PopupMenuItem(value: 'swap', child: Text('Swap sides')),
              PopupMenuItem(
                value: 'undo',
                enabled: w.canUndo && w.canEdit,
                child: const Text('Undo pick / ban'),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: Text('Copy draft JSON'),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Text('Import draft JSON'),
              ),
              const PopupMenuItem(
                value: 'brief',
                child: Text('Copy coaching brief'),
              ),
              const PopupMenuItem(
                value: 'example',
                child: Text('Load Mino + Esme example'),
              ),
            ],
          ),
        ),
        gap(),
        TextField(
          controller: titleController,
          focusNode: titleFocus,
          readOnly: !w.canEdit,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Draft title',
            counterText: '',
          ),
          onChanged: (v) {
            w.draft!.title = v;
            w.changed(analyze: false);
          },
        ),
        gap(20),
        LayoutBuilder(
          builder: (c, size) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: teamColumn('blue', size.maxWidth < 500)),
              const SizedBox(width: 14),
              Expanded(child: teamColumn('red', size.maxWidth < 500)),
            ],
          ),
        ),
        gap(),
        const Divider(),
        gap(12),
        Row(
          children: [
            const Icon(Icons.touch_app_outlined, size: 15, color: muted),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Tap a slot to pick or ban. Used heroes are excluded.',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ),
            if (w.canUndo)
              IconButton(
                tooltip: 'Undo last draft change',
                onPressed: w.canEdit ? w.undo : null,
                icon: const Icon(Icons.undo, size: 19),
              ),
          ],
        ),
      ],
    ),
    padding: const EdgeInsets.all(16),
  );
  Widget teamColumn(String side, bool compact) {
    final lineup = w.draft!.side(side);
    final color = side == 'blue' ? blue : red;
    final hs = lineup.picks
        .map(w.catalog!.hero)
        .whereType<HeroProfile>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: !w.canEdit
              ? null
              : () async {
                  final value = await textDialog(
                    'Team name',
                    initial: lineup.name,
                    maxLength: 32,
                  );
                  if (value != null && value.trim().isNotEmpty) {
                    lineup.name = value.trim();
                    w.changed(analyze: false);
                  }
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(width: 6, height: 6, color: color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    lineup.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: compact ? 10 : 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!compact)
                  Text(
                    '${side.toUpperCase()} SIDE',
                    style: const TextStyle(color: muted, fontSize: 9),
                  ),
              ],
            ),
          ),
        ),
        gap(10),
        ...List.generate(5, (i) {
          final h = w.catalog!.hero(lineup.picks[i]);
          final selected = w.focusSide == side && w.focusIndex == i;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: .06) : ink,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: selected ? color : edge),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () {
                  w.selectFocus(side, i);
                  if (w.canEdit) heroPicker(side, i, false);
                },
                child: Padding(
                  padding: EdgeInsets.all(compact ? 7 : 10),
                  child: Row(
                    children: [
                      HeroAvatar(hero: h, size: compact ? 28 : 39),
                      SizedBox(width: compact ? 6 : 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              roles[i],
                              style: TextStyle(
                                fontSize: compact ? 9 : 10,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              h?.name ?? 'Choose hero',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 11 : 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (h != null && w.canEdit)
                        SizedBox(
                          width: 20,
                          height: 30,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Remove ${h.name}',
                            icon: const Icon(Icons.close, size: 13),
                            onPressed: () => w.removeHero(side, i, false),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        gap(8),
        const Text(
          'BANS · 5 MANUAL SLOTS',
          style: TextStyle(fontSize: 9, color: muted, letterSpacing: 1),
        ),
        gap(10),
        Row(
          children: List.generate(5, (i) {
            final h = w.catalog!.hero(lineup.bans[i]);
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 4 ? 0 : 5),
                child: Tooltip(
                  message: h == null
                      ? 'Ban slot ${i + 1}'
                      : '${h.name} · long press to clear',
                  child: InkWell(
                    onTap: w.canEdit ? () => heroPicker(side, i, true) : null,
                    onLongPress: w.canEdit
                        ? () => w.removeHero(side, i, true)
                        : null,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        HeroAvatar(hero: h, size: compact ? 27 : 39),
                        if (h != null)
                          const Icon(
                            Icons.block,
                            color: Color(0xAAEDA5A1),
                            size: 25,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        gap(12),
        Text(
          '${hs.where((h) => h.frontline).length} frontline · ${hs.where((h) => h.has('cc') || h.has('suppress')).length} control',
          style: const TextStyle(color: muted, fontSize: 10),
        ),
      ],
    );
  }

  Future<void> heroPicker(String side, int index, bool ban) async {
    var search = '', filter = ban ? 'All' : roles[index];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: panel,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => SizedBox(
          height: MediaQuery.sizeOf(c).height * .83,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.viewInsetsOf(c).bottom + 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ban ? 'Ban' : 'Pick'} for ${w.draft!.side(side).name}${ban ? '' : ' · ${roles[index]}'}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                gap(14),
                TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    hintText: 'Search heroes…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (s) => setLocal(() => search = s),
                ),
                gap(12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', ...roles]
                        .map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: ChoiceChip(
                              label: Text(r),
                              selected: filter == r,
                              onSelected: (_) => setLocal(() => filter = r),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                gap(10),
                Expanded(
                  child: Builder(
                    builder: (c) {
                      final heroes =
                          w.catalog!.heroes
                              .where(
                                (h) =>
                                    !w.draft!.used.contains(h.id) &&
                                    (filter == 'All' ||
                                        h.roles.contains(filter)) &&
                                    h.name.toLowerCase().contains(
                                      search.toLowerCase(),
                                    ),
                              )
                              .toList()
                            ..sort((a, b) => a.name.compareTo(b.name));
                      if (heroes.isEmpty) {
                        return const Center(
                          child: Text(
                            'No available heroes match. Try another role or search.',
                          ),
                        );
                      }
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 130,
                          childAspectRatio: MediaQuery.sizeOf(c).width < 400
                              ? 0.85
                              : 1.0,
                        ),
                        itemCount: heroes.length,
                        itemBuilder: (c, i) {
                          final h = heroes[i];
                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                try {
                                  w.assignHero(side, index, ban, h.id);
                                  Navigator.pop(c);
                                } catch (e) {
                                  message('$e');
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(9),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    HeroAvatar(hero: h, size: 42),
                                    gap(9),
                                    Text(
                                      h.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    gap(4),
                                    Text(
                                      h.roles.join(' / '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget notes() => box(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle('Coach’s notebook', trailing: pill('LOCAL CACHE')),
        gap(),
        TextField(
          controller: notesController,
          focusNode: notesFocus,
          readOnly: !w.canEdit,
          minLines: 5,
          maxLines: 10,
          maxLength: 12000,
          style: const TextStyle(fontSize: 13, height: 1.8),
          decoration: const InputDecoration(
            hintText:
                'Win condition, cooldowns, lane plan and review questions…',
            counterText: '',
          ),
          onChanged: (s) {
            w.draft!.notes = s;
            w.changed(analyze: false);
          },
        ),
        gap(9),
        const Text(
          'Local cache is a convenience. Save important drafts to PostgreSQL or copy the JSON.',
          style: TextStyle(fontSize: 10, color: muted, height: 1.6),
        ),
      ],
    ),
  );
  Widget coachPanel() {
    final a = w.analysis;
    final e = a?['emblem'] as Map?;
    return box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(
            '✦ Coach’s corner',
            trailing: pill(
              w.remoteAnalysis ? 'RUST RULES' : 'LOCAL RULES',
              color: lime,
            ),
          ),
          gap(8),
          const Text(
            'Context over copy-paste.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          gap(20),
          DropdownButtonFormField<String>(
            key: ValueKey('${w.focusSide}:${w.focusIndex}'),
            initialValue: '${w.focusSide}:${w.focusIndex}',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Coaching for'),
            items: [
              for (final side in ['blue', 'red'])
                for (var i = 0; i < 5; i++)
                  DropdownMenuItem(
                    value: '$side:$i',
                    child: Text(
                      '${side == 'blue' ? 'Blue' : 'Red'} · ${roles[i]} · ${w.catalog!.hero(w.draft!.side(side).picks[i])?.name ?? 'Empty'}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
            ],
            onChanged: (s) {
              if (s == null) return;
              final p = s.split(':');
              w.selectFocus(p[0], int.parse(p[1]));
            },
          ),
          gap(14),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
              ),
              segments: const [
                ButtonSegment(value: 'balanced', label: Text('Balanced')),
                ButtonSegment(value: 'survival', label: Text('Survival')),
                ButtonSegment(value: 'tempo', label: Text('Tempo')),
              ],
              selected: {w.priority},
              onSelectionChanged: (s) => w.setPriority(s.first),
            ),
          ),
          gap(13),
          if (a?['partial'] == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                w.t(
                  'Partial draft — suggestions will change as picks are added.',
                  'Draft မပြည့်သေးလို့ hero ထပ်ထည့်ရင် suggestion ပြောင်းနိုင်တယ်။',
                ),
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 11,
                  height: 1.7,
                ),
              ),
            ),
          Row(
            children: List.generate(
              3,
              (i) => Expanded(
                child: TextButton(
                  onPressed: () => setState(() => coachTab = i),
                  style: TextButton.styleFrom(
                    foregroundColor: coachTab == i ? lime : muted,
                    backgroundColor: coachTab == i
                        ? lime.withValues(alpha: .07)
                        : null,
                  ),
                  child: Text(
                    ['Emblems', 'Matchup', 'Game plan'][i],
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
          ),
          gap(14),
          if (a == null)
            const Text('Add a hero to begin.')
          else if (coachTab == 0) ...[
            if (e == null)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Pick a hero in the focused role to see its emblem page.',
                ),
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: lime.withValues(alpha: .06),
                  border: Border.all(color: lime.withValues(alpha: .3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hexagon_outlined, size: 35, color: lime),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${e['base']} Emblem',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          gap(5),
                          Text(
                            e['specificity'] == 'scenario_rules'
                                ? 'Scenario-specific starting page'
                                : 'Role template · verify hero mechanics',
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              gap(12),
              ...List.generate(
                3,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: ink,
                      border: Border.all(color: edge),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '0${i + 1}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            '${e['talents'][i]}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.diamond_outlined,
                          size: 18,
                          color: lime,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              gap(6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bolt, color: Colors.amber, size: 31),
                title: const Text(
                  'BATTLE SPELL',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.amber,
                    letterSpacing: 1,
                  ),
                ),
                subtitle: Text(
                  '${e['spell']}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              gap(12),
              adviceBlock(
                w.t('Why this fits', 'ဘာကြောင့် ရွေးထားလဲ'),
                '${e['reason']}',
                color: lime,
              ),
              gap(16),
              adviceBlock(
                w.t('The trade-off', 'Trade-off'),
                '${e['tradeoff']}',
              ),
              gap(16),
              adviceBlock(
                w.t('When to change it', 'ဘယ်အချိန် ပြောင်းမလဲ'),
                '${e['alternative']}',
              ),
            ],
            gap(20),
            const Divider(),
            gap(16),
            const Text(
              'COMPOSITION FITS',
              style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1),
            ),
            gap(9),
            ...(a['candidates'] as List).take(3).map((candidate) {
              final h = w.catalog!.hero(candidate['hero_id'] as String);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: HeroAvatar(hero: h, size: 33),
                title: Text(
                  h?.name ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: Text(
                  (candidate['reasons'] as List).join(' · '),
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
                trailing: IconButton(
                  tooltip: 'Pick ${h?.name}',
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: !w.canEdit || h == null
                      ? null
                      : () {
                          try {
                            w.assignHero(
                              w.focusSide,
                              w.focusIndex,
                              false,
                              h.id,
                            );
                          } catch (e) {
                            message('$e');
                          }
                        },
                ),
              );
            }),
          ] else
            ...promptCards((a[coachTab == 1 ? 'threats' : 'plan'] as List)),
          gap(16),
          const Divider(),
          gap(13),
          Text(
            w.t(
              'Rules use editable hero profiles. No live patch sync or guaranteed counters. Verify talent availability and effects in the game client.',
              'Hero profile တွေပေါ်မူတည်တဲ့ rules ဖြစ်တယ်။ Live patch sync နဲ့ guaranteed counter မဟုတ်ပါ။ Talent ရနိုင်မှုနဲ့ effect ကို game ထဲမှာ ပြန်စစ်ပါ။',
            ),
            style: const TextStyle(color: muted, fontSize: 10, height: 1.8),
          ),
        ],
      ),
    );
  }

  Widget adviceBlock(String title, String body, {Color color = Colors.white}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          gap(7),
          Text(
            body,
            style: const TextStyle(fontSize: 12, color: muted, height: 1.9),
          ),
        ],
      );
  List<Widget> promptCards(List<dynamic> prompts) => prompts.isEmpty
      ? [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No specific rule triggered. Review range, cooldowns and player comfort; this does not imply the draft is safe.',
              style: TextStyle(color: muted, height: 1.8),
            ),
          ),
        ]
      : prompts
            .asMap()
            .entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 19),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '0${entry.key + 1}',
                      style: const TextStyle(color: lime, fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: adviceBlock(
                        '${entry.value['title']}',
                        '${entry.value['body']}',
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList();
  Widget playbookPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'THE PLAN BEHIND THE PICKS',
        'From draft to decisions.',
        'Turn the current lineup into a briefing your team can use.',
        trailing: FilledButton.icon(
          onPressed: () => copyText(w.brief(), 'Coaching brief copied.'),
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy brief'),
        ),
      ),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionTitle(w.draft!.title),
            gap(),
            pill('${w.catalog!.patch['label']}'),
            gap(23),
            ...promptCards(w.analysis?['plan'] as List? ?? []),
          ],
        ),
      ),
      gap(),
      notes(),
      gap(),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionTitle('Matchup priorities'),
            gap(),
            ...promptCards(w.analysis?['threats'] as List? ?? []),
          ],
        ),
      ),
    ],
  );
  Widget signInPrompt(String text) => box(
    Column(
      children: [
        const Icon(Icons.cloud_outlined, color: lime, size: 45),
        gap(),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, height: 1.8),
        ),
        gap(20),
        FilledButton(
          onPressed: authDialog,
          child: const Text('Sign in / create account'),
        ),
        gap(10),
        TextButton(
          onPressed: () => setState(() => page = 4),
          child: const Text('Configure Rust API'),
        ),
      ],
    ),
  );
  Widget sessionsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'KEEP WHAT YOU LEARN',
        'The scrim archive.',
        'PostgreSQL stores your personal and team drafts with revision checks.',
        trailing: IconButton(
          tooltip: 'Refresh sessions',
          onPressed: w.user == null ? null : () => run(w.refreshCloud),
          icon: const Icon(Icons.refresh),
        ),
      ),
      if (w.user == null)
        signInPrompt(
          'Sign in to save and review cloud drafts. Offline practice is available in the Draft tab.',
        )
      else ...[
        Row(
          children: [
            FilterChip(
              label: const Text('Archived drafts'),
              selected: w.archivedView,
              onSelected: (s) {
                w.archivedView = s;
                run(w.refreshCloud);
              },
            ),
            const Spacer(),
            Text(
              '${w.sessions.length} drafts',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
        gap(),
        if (w.sessions.isEmpty)
          box(
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 35),
              child: Center(
                child: Text(
                  'No drafts here yet. Save your current draft to start a review.',
                ),
              ),
            ),
          ),
        ...w.sessions.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: box(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.draft.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      pill(
                        r.canEdit ? 'CAN EDIT' : 'VIEWER',
                        color: r.canEdit ? lime : blue,
                      ),
                    ],
                  ),
                  gap(10),
                  Text(
                    '${r.teamId == null ? 'Personal workspace' : 'Team workspace'} · revision ${r.revision}',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  gap(15),
                  Wrap(
                    spacing: 7,
                    children: r.draft.blue.picks
                        .map(
                          (id) =>
                              HeroAvatar(hero: w.catalog!.hero(id), size: 34),
                        )
                        .toList(),
                  ),
                  gap(17),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: working
                            ? null
                            : () async {
                                if (w.dirty &&
                                    !await confirm(
                                      'Open saved draft?',
                                      'Unsaved work will be replaced. Save or copy your draft first if needed.',
                                    )) {
                                  return;
                                }
                                await run(() => w.open(r));
                                if (mounted) setState(() => page = 0);
                              },
                        child: Text(
                          r.archived ? 'View archived' : 'Open draft',
                        ),
                      ),
                      if (r.canEdit)
                        TextButton(
                          onPressed: working
                              ? null
                              : () => run(
                                  () => w.archive(r),
                                  success: r.archived
                                      ? 'Draft restored.'
                                      : 'Draft archived. You can restore it from Archived drafts.',
                                ),
                          child: Text(r.archived ? 'Restore' : 'Archive'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
  Widget teamPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'PREPARE TOGETHER',
        'Your coaching team.',
        'Owners invite. Coaches edit. Viewers review.',
      ),
      if (w.user == null)
        signInPrompt(
          'Use a team workspace to share drafts and coach notes with named members.',
        )
      else ...[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: working
                  ? null
                  : () async {
                      final name = await textDialog(
                        'Create team',
                        maxLength: 60,
                      );
                      if (name != null && name.trim().isNotEmpty) {
                        await run(
                          () => w.createTeam(name.trim()),
                          success: 'Team created.',
                        );
                      }
                    },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create team'),
            ),
            OutlinedButton.icon(
              onPressed: working
                  ? null
                  : () async {
                      final code = await textDialog(
                        'Join with invite code',
                        maxLength: 64,
                      );
                      if (code != null) {
                        await run(
                          () => w.joinTeam(code),
                          success: 'Joined the team.',
                        );
                      }
                    },
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Join team'),
            ),
            IconButton(
              tooltip: 'Refresh teams',
              onPressed: working ? null : () => run(w.refreshCloud),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        gap(20),
        if (w.teams.isEmpty)
          box(
            const Center(
              child: Padding(
                padding: EdgeInsets.all(25),
                child: Text(
                  'Create a team or join with a one-time invitation.',
                ),
              ),
            ),
          ),
        ...w.teams.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: box(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.groups_outlined, color: lime),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${t['name']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      pill('${t['role']}'.toUpperCase()),
                    ],
                  ),
                  gap(14),
                  Text(
                    t['role'] == 'viewer'
                        ? 'You can read team drafts. Save a personal copy to explore changes.'
                        : 'Select this workspace when saving a new draft to share it with the team.',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.8,
                    ),
                  ),
                  if (t['role'] == 'owner') ...[
                    gap(15),
                    Wrap(
                      spacing: 10,
                      children: ['coach', 'viewer']
                          .map(
                            (role) => OutlinedButton(
                              onPressed: working
                                  ? null
                                  : () => inviteDialog('${t['id']}', role),
                              child: Text('Invite $role'),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        gap(),
        const Text(
          'Invites expire after 24 hours and can be used once. Send the code through your own trusted channel. Shared draft updates appear on refresh; simultaneous edits are protected by revision checks.',
          style: TextStyle(fontSize: 12, color: muted, height: 1.9),
        ),
      ],
    ],
  );
  Widget settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'MAKE ASSUMPTIONS VISIBLE',
        'Workspace settings.',
        'Connect your Rust API and keep patch context explicit.',
      ),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionTitle(
              'Rust API connection',
              trailing: pill(
                w.online ? 'CONNECTED' : 'OFFLINE',
                color: w.online ? lime : Colors.amber,
              ),
            ),
            gap(),
            TextField(
              controller: urlController,
              focusNode: urlFocus,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'API base URL',
                hintText: 'https://your-rust-api.example.com',
              ),
            ),
            gap(12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: working
                      ? null
                      : () => run(
                          () => w.setUrl(urlController.text),
                          success: 'Connection settings saved.',
                        ),
                  child: const Text('Save & connect'),
                ),
                TextButton(
                  onPressed: working ? null : () => run(() => w.setUrl('')),
                  child: const Text('Use offline practice'),
                ),
              ],
            ),
            gap(12),
            const Text(
              'Android emulator: http://10.0.2.2:8080. iOS simulator / web: http://localhost:8080. Use HTTPS for a hosted API. Changing the API disconnects the current account.',
              style: TextStyle(fontSize: 11, color: muted, height: 1.8),
            ),
          ],
        ),
      ),
      gap(),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionTitle('Account'),
            gap(),
            if (w.user != null) ...[
              Text(
                '${w.user!['display_name']}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              gap(6),
              Text('${w.user!['email']}', style: const TextStyle(color: muted)),
              gap(16),
              OutlinedButton(
                onPressed: working
                    ? null
                    : () async {
                        if (!await confirm(
                          'Sign out?',
                          'The cached cloud draft will be cleared from this device. Your server drafts remain saved.',
                        )) {
                          return;
                        }
                        await run(w.logout);
                      },
                child: const Text('Sign out'),
              ),
            ] else ...[
              const Text(
                'Accounts synchronize drafts through PostgreSQL. Practice works without an account.',
                style: TextStyle(color: muted, height: 1.8),
              ),
              gap(),
              FilledButton(
                onPressed: authDialog,
                child: const Text('Sign in / register'),
              ),
            ],
          ],
        ),
      ),
      gap(),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionTitle('Catalog & rules'),
            gap(12),
            OutlinedButton.icon(
              onPressed: working || !w.online
                  ? null
                  : () async {
                      if (!await confirm(
                        'Start with the latest catalog?',
                        'This starts a new empty draft using the latest server catalog. Save or copy your current draft first.',
                      )) {
                        return;
                      }
                      await run(
                        w.useLatestCatalog,
                        success:
                            'Started a draft using the latest server catalog.',
                      );
                      if (mounted) setState(() => page = 0);
                    },
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('New draft with latest catalog'),
            ),
            gap(),
            pill('${w.catalog!.patch['label']}', color: Colors.amber),
            gap(14),
            Text(
              '${w.catalog!.heroes.length} hero profiles · ${w.analysis?['rules_version'] ?? 'rules pending'}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            gap(12),
            Text(
              '${w.catalog!.patch['notes']}',
              style: const TextStyle(color: muted, fontSize: 12, height: 1.8),
            ),
            gap(12),
            const Text(
              'Hero roles and utility tags are coach assumptions. Most emblem pages are starting role templates. No official API, live meta statistics, damage simulator or tournament-format enforcement is included.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.8),
            ),
            gap(),
            const Text(
              'BACKGROUND REFERENCES',
              style: TextStyle(color: lime, fontSize: 10, letterSpacing: 1),
            ),
            gap(9),
            ...(w.catalog!.patch['sources'] as List).map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: SelectableText(
                  '$s',
                  style: const TextStyle(
                    color: blue,
                    fontSize: 11,
                    height: 1.8,
                  ),
                ),
              ),
            ),
            gap(9),
            const Text(
              'Patch updates are imported as versioned catalog files on the server. Old drafts retain their patch ID. Check the actual game-client effects before competitive use.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.8),
            ),
          ],
        ),
      ),
    ],
  );
  Future<void> copyText(String text, String success) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      message(success);
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Copy this text'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(child: SelectableText(text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<String?> textDialog(
    String title, {
    String initial = '',
    int? maxLength,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          onSubmitted: (s) => Navigator.pop(c, s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> importDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import draft JSON'),
        content: SizedBox(
          width: 550,
          child: TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'Paste a native DraftRoom JSON export…',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              try {
                w.importJson(controller.text);
                Navigator.pop(c);
                message('Draft imported.');
              } catch (e) {
                message('$e');
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> save() async {
    if (w.user == null) {
      await authDialog();
      if (w.user == null) return;
    }
    if (!mounted) return;
    var team = w.current?.teamId ?? w.newTeamId;
    if (!w.canEdit) team = null;
    var copy = w.current != null && !w.canEdit;
    final success = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text(w.current == null ? 'Save draft' : 'Save draft changes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (w.current != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Save a new copy'),
                  subtitle: Text(
                    w.canEdit
                        ? 'Keep the original draft unchanged.'
                        : 'You have viewer access. Copy to your own workspace.',
                  ),
                  value: copy,
                  onChanged: w.canEdit
                      ? (v) => setLocal(() => copy = v!)
                      : null,
                ),
              DropdownButtonFormField<String>(
                key: ValueKey('${copy}_$team'),
                initialValue: team ?? 'personal',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Workspace'),
                items: [
                  const DropdownMenuItem(
                    value: 'personal',
                    child: Text('Personal workspace'),
                  ),
                  ...w.teams
                      .where((t) => t['role'] != 'viewer')
                      .map(
                        (t) => DropdownMenuItem(
                          value: '${t['id']}',
                          child: Text(
                            '${t['name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                ],
                onChanged: w.current != null && !copy
                    ? null
                    : (s) => setLocal(() => team = s == 'personal' ? null : s),
              ),
              gap(12),
              const Text(
                'If another coach saved first, your changes will be kept locally. Refresh the latest draft or save a copy.',
                style: TextStyle(fontSize: 12, color: muted, height: 1.8),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (success == true) {
      w.newTeamId = team;
      await run(
        () => w.save(asCopy: copy),
        success: 'Draft saved to PostgreSQL.',
      );
    }
  }

  Future<void> authDialog() async {
    if (w.api.baseUrl.isEmpty) {
      message('Configure your Rust API URL in Settings first.');
      setState(() => page = 4);
      return;
    }
    final email = TextEditingController(),
        password = TextEditingController(),
        name = TextEditingController();
    var register = false, sending = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text(register ? 'Create coach account' : 'Welcome back'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (register) ...[
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    maxLength: 60,
                  ),
                  gap(10),
                ],
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                gap(12),
                TextField(
                  controller: password,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: register ? 'At least 10 characters' : null,
                  ),
                ),
                if (error != null) ...[
                  gap(12),
                  Text(
                    error!,
                    style: const TextStyle(color: red, fontSize: 12),
                  ),
                ],
                gap(12),
                TextButton(
                  onPressed: sending
                      ? null
                      : () => setLocal(() {
                          register = !register;
                          error = null;
                        }),
                  child: Text(
                    register
                        ? 'Already have an account? Sign in'
                        : 'New here? Create an account',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      setLocal(() => sending = true);
                      try {
                        await w.authenticate(
                          email.text,
                          password.text,
                          name: register ? name.text : null,
                        );
                        if (c.mounted) Navigator.pop(c);
                      } catch (e) {
                        if (c.mounted) {
                          setLocal(() {
                            error = '$e';
                            sending = false;
                          });
                        }
                      }
                    },
              child: Text(
                sending
                    ? 'Connecting…'
                    : register
                    ? 'Create account'
                    : 'Sign in',
              ),
            ),
          ],
        ),
      ),
    );
    email.dispose();
    password.dispose();
    name.dispose();
  }

  Future<void> inviteDialog(String teamId, String role) async {
    String? code;
    await run(() async {
      code = await w.invite(teamId, role);
    });
    if (code == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Invite a $role'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'One use · expires in 24 hours',
              style: TextStyle(color: muted),
            ),
            gap(),
            SelectableText(code!, style: const TextStyle(fontSize: 13)),
            gap(),
            const Text(
              'Send this code yourself. Anyone with the code can join in the selected role.',
              style: TextStyle(fontSize: 12, color: muted, height: 1.7),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => copyText(code!, 'Invite code copied.'),
            child: const Text('Copy code'),
          ),
        ],
      ),
    );
  }
}

class HeroAvatar extends StatelessWidget {
  final HeroProfile? hero;
  final double size;
  const HeroAvatar({super.key, required this.hero, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final h = hero;
    final hue = h == null
        ? 210.0
        : h.id.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) % 360).toDouble();
    final color = HSLColor.fromAHSL(1, hue, .25, .3).toColor();
    final initials = h == null
        ? '+'
        : h.name
              .split(RegExp(r'[ .’\-]+'))
              .where((s) => s.isNotEmpty)
              .take(2)
              .map((s) => s[0])
              .join()
              .toUpperCase();
    return Semantics(
      label: h?.name ?? 'Empty slot',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: h == null
                ? [ink, ink]
                : [color, color.withValues(alpha: .25)],
          ),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: h == null ? edge : color),
        ),
        child: Text(
          initials,
          style: TextStyle(
            fontSize: size * .38,
            fontWeight: FontWeight.w700,
            color: h == null ? muted : Colors.white,
          ),
        ),
      ),
    );
  }
}
