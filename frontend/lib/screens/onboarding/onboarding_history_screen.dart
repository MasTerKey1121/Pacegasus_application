import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/onboarding_api.dart';
import '../../providers/program_provider.dart';
import '../../widgets/common.dart';
import '../home/main_shell.dart';
import '../../models/onboarding_data.dart';

const _durationOptions = ['น้อยกว่า 1 เดือน', '1-3 เดือน', '3-6 เดือน', '6-12 เดือน', '1-3 ปี', '3 ปีขึ้นไป'];
const _distanceOptions = ['น้อยกว่า 5 km', '5-10 km', '10-21 km', '21-42 km', 'มากกว่า 42 km'];

class OnboardingHistoryScreen extends ConsumerWidget {
  const OnboardingHistoryScreen({super.key});

  Map<String, dynamic> _buildBody(OnboardingData d) {
    const weeksByDuration = [2, 8, 18, 39, 104, 156];
    const kmByLongestDistance = [2.5, 7.5, 15.5, 31.5, 42.2];
    final duration = d.isCurrentlyTraining == true
        ? d.trainingDuration
        : d.isCurrentlyTraining == false
            ? d.notTrainingDuration
            : null;
    final durationIndex = duration == null ? -1 : _durationOptions.indexOf(duration);
    final distanceIndex = d.longestDistance == null
      ? -1
      : _distanceOptions.indexOf(d.longestDistance!);

    return {
      'hasRunBefore': d.hasRunningExperience,
      'isCurrentlyRunning': d.hasRunningExperience == true ? d.isCurrentlyTraining : false,
      'weeksRunning': durationIndex >= 0 ? weeksByDuration[durationIndex] : null,
      'longestDistanceKm': distanceIndex >= 0 ? kmByLongestDistance[distanceIndex] : null,
      // yearsRunning / best5kSeconds / ... : ไม่มี UI เก็บค่า และเป็น optional ทั้งหมด เลยไม่ส่ง
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(onboardingProvider);
    final ob = ref.watch(onboardingProvider);
    final data = ob.data;
    final user = ref.watch(authProvider).user;
    final hasAnsweredExperience = data.hasRunningExperience != null;
    final needsTrainingAnswer = data.hasRunningExperience == true;
    final hasAnsweredTraining = !needsTrainingAnswer || data.isCurrentlyTraining != null;
    final hasSelectedDuration = !needsTrainingAnswer ||
        (data.isCurrentlyTraining == true
            ? data.trainingDuration != null
            : data.notTrainingDuration != null);
    final canProceed = hasAnsweredExperience &&
        hasAnsweredTraining &&
        hasSelectedDuration &&
        data.longestDistance != null &&
        !ob.isSubmitting;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                Row(children: [
                  RoundIconButton(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Expanded(child: OnboardingProgress(steps: 4, active: 4)),
                ]),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ประวัติการวิ่ง', style: AppText.heading(size: 20)),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ช่วยให้เราประเมินระดับของคุณได้แม่นยำ',
                      style: AppText.body(size: 13, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('เคยซ้อมหรือแข่งวิ่งมาก่อนไหม?',
                              style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              MultiChip(
                                label: 'เคย',
                                selected: data.hasRunningExperience == true,
                                onTap: () => notifier.update((d) => d.hasRunningExperience = true),
                              ),
                              MultiChip(
                                label: 'ไม่เคย',
                                selected: data.hasRunningExperience == false,
                                onTap: () => notifier.update((d) {
                                  d.hasRunningExperience = false;
                                  d.isCurrentlyTraining = null;
                                  d.trainingDuration = null;
                                  d.notTrainingDuration = null;
                                }),
                              ),
                            ],
                          ),
                          if (data.hasRunningExperience == true) ...[
                            const SizedBox(height: 24),
                            Text('ปัจจุบันยังซ้อมอยู่ไหม?',
                                style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                MultiChip(
                                  label: 'ใช่',
                                  selected: data.isCurrentlyTraining == true,
                                  onTap: () => notifier.update((d) {
                                    d.isCurrentlyTraining = true;
                                    d.notTrainingDuration = null;
                                  }),
                                ),
                                MultiChip(
                                  label: 'ไม่',
                                  selected: data.isCurrentlyTraining == false,
                                  onTap: () => notifier.update((d) {
                                    d.isCurrentlyTraining = false;
                                    d.trainingDuration = null;
                                  }),
                                ),
                              ],
                            ),
                          ],
                          if (data.isCurrentlyTraining == true) ...[
                            const SizedBox(height: 24),
                            Text('ซ้อมต่อเนื่องมานานเท่าไหร่แล้ว?',
                                style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _durationOptions
                                  .map((o) => MultiChip(
                                        label: o,
                                        selected: data.trainingDuration == o,
                                        onTap: () => notifier.update((d) => d.trainingDuration = o),
                                      ))
                                  .toList(),
                            ),
                          ],
                          if (data.isCurrentlyTraining == false) ...[
                            const SizedBox(height: 24),
                            Text('ไม่ได้ซ้อมมานานเท่าไหร่แล้ว?',
                                style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _durationOptions
                                  .map((o) => MultiChip(
                                        label: o,
                                        selected: data.notTrainingDuration == o,
                                        onTap: () => notifier.update((d) => d.notTrainingDuration = o),
                                      ))
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 24),
                          Text('เคยวิ่งไกลสุดเท่าไหร?',
                              style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _distanceOptions
                                .map((o) => MultiChip(
                                      label: o,
                                      selected: data.longestDistance == o,
                                      onTap: () => notifier.update((d) => d.longestDistance = o),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 26),
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('สรุปประวัติการวิ่ง', style: AppText.heading(size: 14)),
                                const SizedBox(height: 12),
                                _SummaryRow(
                                  'ประสบการณ์การวิ่ง',
                                  data.hasRunningExperience == true ? 'เคยซ้อม/แข่งวิ่ง' : 'ไม่เคย',
                                ),
                                _SummaryRow('ชื่อ', _displayName(user)),
                                _SummaryRow('เพศ', data.gender ?? 'ไม่ระบุ'),
                                _SummaryRow('อายุ', _ageLabel(data)),
                                _SummaryRow('น้ำหนัก', _withUnit(data.weightKg, 'กก.')),
                                _SummaryRow('ส่วนสูง', _withUnit(data.heightCm, 'ซม.')),
                                _SummaryRow('เป้าหมายสุขภาพ', data.healthGoal ?? 'ไม่ได้ตั้งเป้าหมาย'),
                                _SummaryRow('เป้าหมายระยะทาง', data.distanceGoal ?? 'ไม่ได้ตั้งเป้าหมาย'),
                                _SummaryRow(
                                  'เป้าหมายเวลา',
                                  data.distanceGoal == null
                                      ? 'ไม่ได้เลือกเป้าหมายระยะทาง'
                                      : _finishTimeLabel(data.targetFinishTime),
                                ),
                                _SummaryRow('โรคประจำตัว', _selectedItems(data.conditions)),
                                _SummaryRow('อาการบาดเจ็บที่เคยเป็น', _selectedItems(data.pastInjuries)),
                                _SummaryRow('อาการบาดเจ็บปัจจุบัน', _selectedItems(data.currentInjuries)),
                                _SummaryRow('ระยะวิ่งไกลสุด', data.longestDistance ?? 'ไม่ระบุ'),
                              ],
                            ),
                          ),
                          if (ob.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(ob.errorMessage!, style: AppText.body(size: 12.5, color: AppColors.red1)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                GradientButton(
                  label: ob.isSubmitting ? 'กำลังบันทึก...' : 'เริ่มใช้งาน ✓',
                  gradient: AppColors.greenGradient,
                  onTap: canProceed
                      ? () async {
                          final ok = await notifier.submitStep(
                            () async {
                              final onboardingResponse = await ref
                                  .read(onboardingApiProvider)
                                  .step4(_buildBody(data));
                              final responseData = onboardingResponse['data']
                                  as Map<String, dynamic>?;
                              final level = responseData?['runningExperienceLevel']
                                  as String?;
                              if (level == null || level.isEmpty) {
                                throw StateError(
                                  'ไม่พบระดับการวิ่งที่ได้จาก Onboarding',
                                );
                              }

                              // Keep the derived level locally for the plan
                              // registration step.  Do not call API 5.1 here:
                              // the user registers the plan after Daily Wellness.
                              ref.read(programProvider).setOnboardingLevel(level);
                            },
                          );
                          if (ok && context.mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const MainShell()),
                              (route) => false,
                            );
                          }
                        }
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _displayName(Map<String, dynamic>? user) {
  final name = user?['displayName']?.toString().trim();
  if (name != null && name.isNotEmpty) return name;
  final email = user?['email']?.toString().trim();
  return email == null || email.isEmpty ? 'ไม่ระบุ' : email;
}

String _ageLabel(OnboardingData data) {
  final day = int.tryParse(data.day);
  final month = int.tryParse(data.month);
  final year = int.tryParse(data.year);
  if (day == null || month == null || year == null) return 'ไม่ระบุ';

  final today = DateTime.now();
  var age = today.year - year;
  if (month > today.month || (month == today.month && day > today.day)) age--;
  return age < 0 ? 'ไม่ระบุ' : '$age ปี';
}

String _withUnit(String value, String unit) =>
    value.trim().isEmpty ? 'ไม่ระบุ' : '${value.trim()} $unit';

String _selectedItems(Set<String> values) =>
    values.isEmpty ? 'ไม่มี' : values.join(', ');

String _finishTimeLabel(String value) {
  if (value.trim().isEmpty) return 'ไม่ได้ตั้งเป้าเวลา';
  final parts = value.split(':');
  if (parts.length != 2) return value;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  if (hours == null || minutes == null) return value;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')} ชม.';
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: AppText.body(size: 13, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppText.body(size: 13, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
