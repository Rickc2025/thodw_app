import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/state_cache.dart';
import '../services/divers_service.dart';
import '../services/provisioning_service.dart';

import '../core/constants.dart';
import '../core/departments.dart';
import '../core/utils.dart';
import '../widgets/top_alert.dart';
import '../widgets/top_snack.dart';
import '../app.dart';
import 'history_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Box diversBox;

  int currentlyIn = 0;
  Timer? _timer;
  bool darkMode = false;
  bool _provisioningBusy = false;
  bool _managedUsersBusy = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _diversSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _checkinsSub;
  List<Map<String, dynamic>> _divers = [];

  @override
  void initState() {
    super.initState();
    diversBox = Hive.box('divers');
    darkMode = Hive.box('prefs').get('darkMode', defaultValue: false);
    _update();
    _loadDivers();
    _diversSub = FirebaseFirestore.instance
        .collection('divers')
        .snapshots()
        .listen((_) => _loadDivers(), onError: (_, __) => _loadDivers());
    _checkinsSub = FirebaseFirestore.instance
        .collection('checkins')
        .snapshots()
        .listen((_) => _update(), onError: (_, __) => _update());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  Future<void> _update() async {
    if (mounted) setState(() => currentlyIn = StateCache.currentlyIn());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _diversSub?.cancel();
    _checkinsSub?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get divers => _divers;

  Future<void> _loadDivers() async {
    try {
      _divers = await DiversService.getDivers();
    } catch (_) {
      final stored = diversBox.get('diversList', defaultValue: <Map>[]);
      _divers = List<Map>.from(
        stored,
      ).map((e) => Map<String, dynamic>.from(e)).toList();
    }
    _divers.sort(
      (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
        (b['name'] ?? '').toString().toLowerCase(),
      ),
    );
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    TopSnack.show(context, msg, duration: const Duration(seconds: 2));
  }

  bool get _isAdmin => MyApp.of(context)?.isAdmin == true;

  Future<bool> _confirmCurrentPassword({
    String title = 'Verify current password',
    String message = 'Enter your current password to continue.',
  }) async {
    final controller = TextEditingController();
    String? error;

    final verified = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await MyApp.of(
                    context,
                  )?.verifyCurrentPassword(controller.text);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (e) {
                  setDialogState(
                    () => error = e.toString().replaceFirst('Exception: ', ''),
                  );
                }
              },
              child: const Text('Verify'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return verified == true;
  }

  Future<void> _showManageLoginUsersDialog() async {
    if (_managedUsersBusy) return;
    setState(() => _managedUsersBusy = true);
    try {
      final users = await MyApp.of(context)?.listManagedUsers() ?? const [];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final screenWidth = MediaQuery.of(context).size.width;
            final dialogWidth = screenWidth < 420 ? screenWidth * 0.92 : 560.0;
            final compact = screenWidth < 520;

            return AlertDialog(
              title: const Text('Manage login users'),
              content: SizedBox(
                width: dialogWidth,
                child: users.isEmpty
                    ? const Text('No login users found.')
                    : ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.6,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: users.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final user = users[index];
                            final subtitle = [
                              user.melcoId,
                              user.role.toUpperCase(),
                              if (user.disabled) 'DISABLED',
                              if (user.requirePasswordChange)
                                'PASSWORD CHANGE REQUIRED',
                              if (user.bootstrapAdmin) 'BOOTSTRAP ADMIN',
                            ].join(' • ');

                            Future<void> handleReset() async {
                              final ok = await _confirmCurrentPassword(
                                title: 'Verify before password reset',
                                message:
                                    'Enter your current password before resetting this user password.',
                              );
                              if (!ok) return;
                              try {
                                final result = await MyApp.of(
                                  context,
                                )?.resetManagedUserPassword(user.uid);
                                if (!dialogContext.mounted || result == null) {
                                  return;
                                }
                                _snack(
                                  'Password reset for ${result.displayName} (${result.email}). Temporary password: ${result.password}',
                                );
                              } catch (e) {
                                _snack(
                                  e.toString().replaceFirst('Exception: ', ''),
                                );
                              }
                            }

                            Future<void> handleToggleDisabled() async {
                              final ok = await _confirmCurrentPassword(
                                title: user.disabled
                                    ? 'Verify before enabling user'
                                    : 'Verify before disabling user',
                                message: user.disabled
                                    ? 'Enter your current password before enabling this user.'
                                    : 'Enter your current password before disabling this user.',
                              );
                              if (!ok) return;
                              try {
                                await MyApp.of(context)?.setManagedUserDisabled(
                                  uid: user.uid,
                                  disabled: !user.disabled,
                                );
                                if (!dialogContext.mounted) return;
                                Navigator.pop(dialogContext);
                                _snack(
                                  user.disabled
                                      ? 'User enabled.'
                                      : 'User disabled.',
                                );
                                _showManageLoginUsersDialog();
                              } catch (e) {
                                _snack(
                                  e.toString().replaceFirst('Exception: ', ''),
                                );
                              }
                            }

                            final actions = compact
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton(
                                          onPressed: handleReset,
                                          child: const Text('Reset Password'),
                                        ),
                                      ),
                                      if (!user.bootstrapAdmin) ...[
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton(
                                            onPressed: handleToggleDisabled,
                                            child: Text(
                                              user.disabled ? 'Enable' : 'Disable',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  )
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton(
                                        onPressed: handleReset,
                                        child: const Text('Reset Password'),
                                      ),
                                      if (!user.bootstrapAdmin)
                                        OutlinedButton(
                                          onPressed: handleToggleDisabled,
                                          child: Text(
                                            user.disabled ? 'Enable' : 'Disable',
                                          ),
                                        ),
                                    ],
                                  );

                            return Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.displayName.isEmpty
                                          ? user.melcoId
                                          : user.displayName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(subtitle),
                                    const SizedBox(height: 12),
                                    actions,
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        _snack(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _managedUsersBusy = false);
    }
  }

  Future<void> _showCreateLoginUserDialog() async {
    final nameController = TextEditingController();
    final melcoController = TextEditingController();
    String role = 'operator';
    String? error;

    final result = await showDialog<ProvisioningResult>(
      context: context,
      builder: (dialogContext) {
        bool saving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Create login user'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Employee name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: melcoController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Melco ID'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(
                      value: 'operator',
                      child: Text('Operator'),
                    ),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => role = value);
                  },
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => error = null);
                        final ok = await _confirmCurrentPassword(
                          title: 'Verify before creating login user',
                          message:
                              'Enter your current password before creating a new login user.',
                        );
                        if (!ok) {
                          return;
                        }
                        setDialogState(() => saving = true);
                        try {
                          final provisioned = await MyApp.of(context)
                              ?.createLoginUser(
                                melcoId: melcoController.text,
                                displayName: nameController.text,
                                role: role,
                              );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, provisioned);
                          }
                        } catch (e) {
                          setDialogState(
                            () => error = e.toString().replaceFirst(
                              'Exception: ',
                              '',
                            ),
                          );
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => saving = false);
                          }
                        }
                      },
                child: const Text('Create'),
              ),
            ],
          ),
        );
      },
    );

    nameController.dispose();
    melcoController.dispose();

    if (!mounted || result == null) return;
    _snack(
      'Login user ready for ${result.displayName} (${result.email}). Temporary password: ${result.password}',
    );
  }

  void _showAddDialog() {
    if (!_isAdmin) {
      _snack('Only admins can add divers.');
      return;
    }
    _showDiverDialog(diver: null);
  }

  // (Old remove dialog removed; editing covers name/department updates. Implement removal if needed.)

  void _showEditDiverDialog(Map diver) {
    if (!_isAdmin) {
      _snack('Only admins can edit divers.');
      return;
    }
    _showDiverDialog(diver: diver);
  }

  void _showDiverDialog({Map? diver}) {
    final checkinsBox = Hive.box('checkins');
    final bool isEdit = diver != null;
    final String? diverId = isEdit ? (diver['id']?.toString()) : null;
    String oldName = isEdit ? (diver['name'] ?? '').toString() : '';
    String newName = isEdit ? oldName : '';
    // Persist a single controller instance across dialog rebuilds so the
    // typed name doesn't disappear when other controls trigger setState.
    final TextEditingController nameController = TextEditingController(
      text: isEdit ? newName : '',
    );
    String selectedDepartment = isEdit
        ? (diver['department'] ?? '').toString()
        : (getDepartmentChoicesForAdd().isNotEmpty
              ? getDepartmentChoicesForAdd().first
              : 'SHOW DIVERS');
    if (selectedDepartment.isEmpty) {
      final choices = getDepartmentChoicesForAdd();
      if (choices.isNotEmpty) selectedDepartment = choices.first;
    }
    String? selectedTeam = selectedDepartment == 'SHOW DIVERS'
        ? (isEdit ? (diver['team'] ?? teams.first).toString() : teams.first)
        : null;
    bool gasAir = isEdit ? (diver['gasAir'] ?? false) == true : false;
    bool gasNitrox = isEdit ? (diver['gasNitrox'] ?? false) == true : false;
    bool gffm = isEdit ? (diver['gffm'] ?? false) == true : false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(isEdit ? 'Edit Diver' : 'Add Diver'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: !isEdit,
                  decoration: const InputDecoration(
                    labelText: 'Diver Name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => newName = v,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedDepartment,
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final dep in getDepartmentChoicesForAdd())
                      DropdownMenuItem(value: dep, child: Text(dep)),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setDialog(() {
                      selectedDepartment = val;
                      if (selectedDepartment == 'SHOW DIVERS') {
                        selectedTeam ??= teams.first;
                      } else {
                        selectedTeam = null;
                      }
                    });
                  },
                ),
                if (selectedDepartment == 'SHOW DIVERS') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedTeam,
                    decoration: const InputDecoration(
                      labelText: 'Team',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final t in teams)
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (val) => setDialog(() => selectedTeam = val),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Gas:',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      selected: gasAir,
                      label: const Text('Air'),
                      selectedColor: Colors.blue[300],
                      onSelected: (v) => setDialog(() {
                        gasAir = v;
                        if (v) gasNitrox = false;
                      }),
                    ),
                    FilterChip(
                      selected: gasNitrox,
                      label: const Text('Nitrox'),
                      selectedColor: Colors.green[400],
                      onSelected: (v) => setDialog(() {
                        gasNitrox = v;
                        if (v) gasAir = false;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Guardian Full Face Mask:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Switch(
                      value: gffm,
                      onChanged: (v) => setDialog(() => gffm = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (isEdit)
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: ctx,
                    builder: (confirmCtx) => AlertDialog(
                      title: const Text('Remove Diver'),
                      content: Text(
                        "Are you sure you want to remove '$oldName'?",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmCtx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.pop(confirmCtx, true),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    // Do not allow removal if diver is currently in water.
                    if (diverId != null && StateCache.diverIsInWater(diverId)) {
                      _snack("Cannot remove diver who is currently IN WATER.");
                      return;
                    }
                    if (diverId != null) {
                      await DiversService.removeDiver(diverId);
                    }
                    // Firestore cascade handles check-ins; remove local legacy entry if present.
                    try {
                      if (diverId != null) checkinsBox.delete(diverId);
                    } catch (_) {}
                    Navigator.pop(ctx);
                    setState(() {});
                    _snack('Diver removed.');
                  }
                },
                child: const Text(
                  'Remove Diver',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (newName.trim().isEmpty) {
                  _snack("Name can't be empty.");
                  return;
                }
                // Require at least one gas selection (Air or Nitrox)
                if (!gasAir && !gasNitrox) {
                  _snack("Select gas: Air or Nitrox.");
                  return;
                }
                // Enforce duplicate rules:
                // - Same name within the same department is NOT allowed
                // - For SHOW DIVERS, same name within the same team color is NOT allowed
                // - Same name across different departments (or different team colors in SHOW DIVERS) is allowed
                bool _clash() {
                  final String n = newName.trim().toLowerCase();
                  final String dep = (selectedDepartment).toString();
                  final String depL = dep.toLowerCase();
                  final String teamL = (selectedTeam ?? '')
                      .toString()
                      .toLowerCase();
                  for (final d in _divers) {
                    final String dId = (d['id'] ?? '').toString();
                    if (isEdit && diverId != null && dId == diverId)
                      continue; // ignore self when editing
                    final String dn = (d['name'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();
                    final String dd = (d['department'] ?? '')
                        .toString()
                        .toLowerCase();
                    final String dt = (d['team'] ?? '')
                        .toString()
                        .toLowerCase();
                    if (dn != n) continue;
                    if (depL != 'show divers') {
                      if (dd == depL)
                        return true; // same department + same name
                    } else {
                      if (dd == depL && dt == teamL)
                        return true; // same team color in SHOW DIVERS + same name
                    }
                  }
                  return false;
                }

                if (_clash()) {
                  if (selectedDepartment == 'SHOW DIVERS') {
                    _snack(
                      "A diver named '" +
                          newName.trim() +
                          "' already exists in SHOW DIVERS (team " +
                          (selectedTeam ?? '') +
                          ").",
                    );
                  } else {
                    _snack(
                      "A diver named '" +
                          newName.trim() +
                          "' already exists in " +
                          selectedDepartment +
                          ".",
                    );
                  }
                  return;
                }
                if (isEdit) {
                  // Update diver record
                  if (diverId == null) {
                    _snack('Could not update: missing diver id.');
                    return;
                  }
                  await DiversService.updateDiver(diverId, {
                    'name': newName.trim(),
                    'department': selectedDepartment,
                    'team': selectedDepartment == 'SHOW DIVERS'
                        ? selectedTeam
                        : null,
                    'gasAir': gasAir,
                    'gasNitrox': gasNitrox,
                    'gffm': gffm,
                  });
                  Navigator.pop(ctx);
                  setState(() {});
                  _snack('Diver updated.');
                } else {
                  // Add new diver
                  await DiversService.createDiver({
                    'name': newName.trim(),
                    'department': selectedDepartment,
                    'team': selectedDepartment == 'SHOW DIVERS'
                        ? selectedTeam
                        : null,
                    'gasAir': gasAir,
                    'gasNitrox': gasNitrox,
                    'gffm': gffm,
                  });
                  Navigator.pop(ctx);
                  setState(() {});
                  _snack('Diver added!');
                }
              },
              child: Text(isEdit ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAbout() {
    final scale = appScale(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('About'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'AQX Dive Log App',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Version: 1.0.0',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 2),
            Text('Updated: 2026-mar-16 at 12:46 AM'),
            SizedBox(height: 10),
            Text('Developed by: Ricardo Costa Silva'),
            SizedBox(height: 6),
            SelectableText('Contact: akosiricardocosta@gmail.com'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(fontSize: 14 * scale)),
          ),
        ],
      ),
    );
  }

  void _toggleDark(bool value) async {
    MyApp.of(context)?.toggleDarkMode(value);
    setState(() => darkMode = value);
    Hive.box('prefs').put('darkMode', value);
    try {
      await FirebaseFirestore.instance.collection('prefs').doc('app').set({
        'darkMode': value,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _logout() async {
    await MyApp.of(context)?.logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _changePassword() async {
    final currentController = TextEditingController();
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    String? error;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Change account password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final current = currentController.text.trim();
                  final next = controller.text.trim();
                  final confirm = confirmController.text.trim();
                  if (current.isEmpty) {
                    setDialogState(
                      () => error = 'Enter your current password first.',
                    );
                    return;
                  }
                  if (next.length < 6) {
                    setDialogState(
                      () => error = 'Password must be at least 6 characters.',
                    );
                    return;
                  }
                  if (next != confirm) {
                    setDialogState(() => error = 'Passwords do not match.');
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'current': current,
                    'next': next,
                  });
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    currentController.dispose();
    controller.dispose();
    confirmController.dispose();

    if (result == null) return;
    try {
      await MyApp.of(
        context,
      )?.changePassword(result['next']!, currentPassword: result['current']);
      if (mounted) _snack('Password updated.');
    } catch (e) {
      if (mounted) {
        _snack(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  void _resetCheckIns() {
    if (!_isAdmin) {
      _snack('Only admins can run New Day Reset.');
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("New Day Reset"),
        content: const Text(
          "This will clear today's CHECKED‑IN list (not IN WATER) and reset Show Deck AQC groups.\nDivers currently IN WATER will remain checked‑in and carry over.",
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Reset"),
            onPressed: () async {
              // Clear only those checked‑in who are NOT currently IN WATER
              final coll = FirebaseFirestore.instance.collection('checkins');
              final ids = StateCache.checkedInIds();
              final batch = FirebaseFirestore.instance.batch();
              for (final id in ids) {
                if (!StateCache.diverIsInWater(id)) {
                  batch.delete(coll.doc(id));
                }
              }
              await batch.commit();

              // Clear persisted Show Deck AQC assignments for the new day.
              final aqcColl = FirebaseFirestore.instance.collection(
                'showdeck_aqc',
              );
              final aqcSnap = await aqcColl.get();
              if (aqcSnap.docs.isNotEmpty) {
                final aqcBatch = FirebaseFirestore.instance.batch();
                for (final doc in aqcSnap.docs) {
                  aqcBatch.delete(doc.reference);
                }
                await aqcBatch.commit();
              }

              if (context.mounted) {
                Navigator.pop(context);
                _snack("Checked‑In list and Show Deck AQC groups cleared.");
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = appScale(context);
    final list = divers;

    return Scaffold(
      body: Stack(
        children: [
          TopAlert(
            currentlyIn: currentlyIn,
            onTap: () {
              // Quick jump to live IN WATER view in Log
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const HistoryPage(selectedColor: "IN WATER"),
                ),
              );
            },
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, size: 28 * scale),
                      onPressed: () => Navigator.pop(context),
                    ),
                    SizedBox(width: 12 * scale),
                    Text(
                      "Settings",
                      style: TextStyle(
                        fontSize: 28 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'About',
                      icon: Icon(Icons.info_outline, size: 26 * scale),
                      onPressed: _showAbout,
                    ),
                  ],
                ),
                SizedBox(height: 10 * scale),
                // Top action buttons
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50 * scale,
                              child: ElevatedButton.icon(
                                icon: Icon(Icons.add, size: 22 * scale),
                                label: Text(
                                  'Add Diver',
                                  style: TextStyle(fontSize: 16 * scale),
                                ),
                                onPressed: _showAddDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      14 * scale,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12 * scale),
                          Expanded(
                            child: SizedBox(
                              height: 50 * scale,
                              child: ElevatedButton.icon(
                                icon: Icon(Icons.refresh, size: 22 * scale),
                                label: Text(
                                  'New Day Reset (Checked‑In only)',
                                  style: TextStyle(fontSize: 16 * scale),
                                ),
                                onPressed: _resetCheckIns,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red[600],
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      14 * scale,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12 * scale),
                          Expanded(
                            child: SizedBox(
                              height: 50 * scale,
                              child: ElevatedButton.icon(
                                icon: Icon(Icons.history, size: 20 * scale),
                                label: Text(
                                  'History of Dives',
                                  style: TextStyle(fontSize: 16 * scale),
                                ),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const HistoryPage(
                                      selectedColor: 'ALL',
                                      showTabs: false,
                                    ),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[200],
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      14 * scale,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_isAdmin) ...[
                        SizedBox(height: 12 * scale),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Admin bootstrap stays server-side. Use Create Login User for new accounts and Manage Login Users for resets / enable / disable actions.',
                            style: TextStyle(
                              fontSize: 13 * scale,
                              color: Colors.blueGrey[700],
                            ),
                          ),
                        ),
                        SizedBox(height: 10 * scale),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48 * scale,
                                child: OutlinedButton.icon(
                                  onPressed: _provisioningBusy
                                      ? null
                                      : _showCreateLoginUserDialog,
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: const Text('Create Login User'),
                                ),
                              ),
                            ),
                            SizedBox(width: 12 * scale),
                            Expanded(
                              child: SizedBox(
                                height: 48 * scale,
                                child: OutlinedButton.icon(
                                  onPressed: _managedUsersBusy
                                      ? null
                                      : _showManageLoginUsersDialog,
                                  icon: const Icon(
                                    Icons.manage_accounts_outlined,
                                  ),
                                  label: const Text('Manage Login Users'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 12 * scale),
                SizedBox(height: 12 * scale),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "Dark theme",
                      style: TextStyle(
                        fontSize: 20 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    value: darkMode,
                    onChanged: _toggleDark,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _changePassword,
                          icon: const Icon(Icons.key_rounded),
                          label: const Text('Change password'),
                        ),
                      ),
                      SizedBox(width: 12 * scale),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _logout,
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('Logout'),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 8 * scale),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                    child: list.isEmpty
                        ? Center(
                            child: Text(
                              "No divers yet.\nTap 'Add Diver' to get started.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20 * scale,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final d = list[i];
                              String subtitle = d['department'] ?? '';
                              if (d['department'] == "SHOW DIVERS" &&
                                  d['team'] != null) {
                                subtitle += " - ${d['team']}";
                              }
                              return Container(
                                color: i % 2 == 0
                                    ? Colors.white
                                    : Colors.grey[100],
                                child: ListTile(
                                  title: Text(
                                    d['name'] ?? '',
                                    style: TextStyle(fontSize: 20 * scale),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        subtitle,
                                        style: TextStyle(fontSize: 14 * scale),
                                      ),
                                      Builder(
                                        builder: (_) {
                                          final bool gasAir =
                                              (d['gasAir'] ?? false) == true;
                                          final bool gasNitrox =
                                              (d['gasNitrox'] ?? false) == true;
                                          final bool gffm =
                                              (d['gffm'] ?? false) == true;
                                          final chips = <Widget>[];
                                          if (gasAir) {
                                            chips.add(
                                              Chip(
                                                label: const Text('AIR'),
                                                backgroundColor:
                                                    Colors.blue[300],
                                                labelStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            );
                                          }
                                          if (gasNitrox) {
                                            chips.add(
                                              Chip(
                                                label: const Text('NITROX'),
                                                backgroundColor:
                                                    Colors.green[400],
                                                labelStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            );
                                          }
                                          if (gffm) {
                                            chips.add(
                                              Chip(
                                                label: const Text('GFFM'),
                                                backgroundColor: Colors.black87,
                                                labelStyle: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            );
                                          }
                                          if (chips.isEmpty)
                                            return const SizedBox.shrink();
                                          return Padding(
                                            padding: EdgeInsets.only(
                                              top: 4 * scale,
                                            ),
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: -6,
                                              children: chips,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      Icons.edit,
                                      color: Colors.blueGrey[700],
                                      size: 22 * scale,
                                    ),
                                    onPressed: () => _showEditDiverDialog(d),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
