import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../widgets/common.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../providers/program_provider.dart';
import '../auth/login_screen.dart';
import '../training/training_schedule_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(programProvider).loadTemplates());
  }

  Future<void> _logout() async {
    // เคลียร์ session ผ่าน authProvider (ยิง /api/auth/logout + ลบ refresh token
    // ที่เก็บไว้ใน secure storage) แทนการ Navigator.push เฉยๆ แบบเดิม
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: Text('ลบบัญชีถาวร?', style: AppText.heading(size: 17)),
        content: Text(
          'ข้อมูลทั้งหมดของคุณ (โปรไฟล์ ประวัติการวิ่ง เควส คอยน์) จะถูกลบและกู้คืนไม่ได้',
          style: AppText.body(size: 13.5, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('ยกเลิก', style: AppText.body(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('ลบบัญชี', style: AppText.body(color: AppColors.red1, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      final authApi = ref.read(authApiProvider);
      await authApi.deleteAccount();
      // ลบสำเร็จฝั่ง server แล้ว เคลียร์ session ฝั่ง client ต่อ
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      Navigator.of(context)
          .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    } catch (_) {
      if (mounted) showAppToast(context, 'ลบบัญชีไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final program = ref.watch(programProvider);
    final matchingTemplates = program.templates
        .where((item) => item['level'] == program.selectedTemplateLevel);
    final template = matchingTemplates.isEmpty ? null : matchingTemplates.first;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ตั้งค่า', style: AppText.heading(size: 20)),
          const SectionLabel(title: 'บัญชีและโปรไฟล์'),
          _MenuTile(icon: Icons.person_outline, label: 'แก้ไขโปรไฟล์', onTap: () {}),
          const SizedBox(height: 10),
          if (program.isRegistered)
            _MenuTile(
              icon: Icons.directions_run_rounded,
              label: 'แก้ไขโปรแกรมวิ่ง',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _TrainingProgramDetailsScreen(
                    title: template?['goal_label']?.toString() ?? 'โปรแกรมวิ่งของฉัน',
                    description: template?['description']?.toString() ??
                        'ตารางซ้อมที่คุณลงทะเบียนไว้ สามารถดูและจัดสัปดาห์ปัจจุบันหรืออนาคตได้',
                    onDelete: _confirmDeleteProgram,
                  ),
                ),
              ),
            ),
          if (program.isRegistered) const SizedBox(height: 10),
          _MenuTile(icon: Icons.menu_book_outlined, label: 'ประวัติการวิ่ง', onTap: () {}),
          const SizedBox(height: 10),
          _MenuTile(icon: Icons.flag_outlined, label: 'เป้าหมายการวิ่ง', onTap: () {}),
          const SectionLabel(title: 'การเชื่อมต่อ'),
          _MenuTile(icon: Icons.link_rounded, label: 'เชื่อมต่อ API ภายนอก', onTap: () {}),
          const SectionLabel(title: 'อื่นๆ'),
          _MenuTile(
            icon: Icons.logout_rounded,
            label: 'ออกจากระบบ',
            danger: true,
            onTap: _logout,
          ),
          const SizedBox(height: 10),
          _MenuTile(
            icon: Icons.delete_forever_rounded,
            label: _deleting ? 'กำลังลบบัญชี...' : 'ลบบัญชี',
            danger: true,
            onTap: _deleting ? () {} : _confirmDeleteAccount,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteProgram() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: Text('จบโปรแกรมก่อนกำหนด?', style: AppText.heading(size: 17)),
        content: Text(
          'รายการซ้อมที่ยังไม่ได้เริ่มทั้งหมดจะถูกลบ และคุณจะไม่สามารถกลับมาทำโปรแกรมนี้ต่อได้ หากต้องการฝึกโปรแกรมอีกครั้ง ต้องลงทะเบียนและเริ่มตารางใหม่ ประวัติการซ้อมที่เริ่มหรือเสร็จแล้วจะยังคงอยู่',
          style: AppText.body(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('กลับไปก่อน', style: AppText.body(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('จบโปรแกรม', style: AppText.body(color: AppColors.red1)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    showAppToast(context, 'ยังจบโปรแกรมไม่ได้ เนื่องจากระบบยังไม่มี API รองรับการยกเลิกโปรแกรม');
  }
}

class _TrainingProgramDetailsScreen extends StatelessWidget {
  const _TrainingProgramDetailsScreen({
    required this.title,
    required this.description,
    required this.onDelete,
  });

  final String title;
  final String description;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      RoundIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 14),
                      Text('แก้ไขโปรแกรมวิ่ง', style: AppText.heading(size: 19)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _TrainingProgramTile(
                    title: title,
                    description: description,
                    onEdit: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TrainingScheduleScreen(),
                      ),
                    ),
                    onDelete: onDelete,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _TrainingProgramTile extends StatefulWidget {
  const _TrainingProgramTile({
    required this.title,
    required this.description,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final String description;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_TrainingProgramTile> createState() => _TrainingProgramTileState();
}

class _TrainingProgramTileState extends State<_TrainingProgramTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          children: [
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.purple1.withOpacity(.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.directions_run_rounded, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.title,
                        style: AppText.body(size: 14, weight: FontWeight.w600)),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? .25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 16),
              Container(height: 1, color: AppColors.border),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.title, style: AppText.heading(size: 16)),
              ),
              const SizedBox(height: 4),
              Text(widget.description,
                  style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlineButton(label: 'แก้ไข', onTap: widget.onEdit),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlineButton(label: 'จบโปรแกรม', onTap: widget.onDelete),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        borderColor: danger ? AppColors.red1.withOpacity(.4) : AppColors.border,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.05),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: danger ? AppColors.red1 : AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: AppText.body(size: 14, weight: FontWeight.w600, color: danger ? AppColors.red1 : AppColors.textPrimary)),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
