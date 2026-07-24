import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../services/onboarding_api.dart';
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
    final distanceIndex = _distanceOptions.indexOf(d.longestDistance);

    return {
      'hasRunBefore': d.hasRunningExperience,
      'isCurrentlyRunning': d.hasRunningExperience == true ? d.isCurrentlyTraining : null,
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
    final hasAnsweredExperience = data.hasRunningExperience != null;
    final needsTrainingAnswer = data.hasRunningExperience == true;
    final hasAnsweredTraining = !needsTrainingAnswer || data.isCurrentlyTraining != null;
    final hasSelectedDuration = !needsTrainingAnswer ||
        (data.isCurrentlyTraining == true
            ? data.trainingDuration != null
            : data.notTrainingDuration != null);
    final canProceed = hasAnsweredExperience && hasAnsweredTraining && hasSelectedDuration && !ob.isSubmitting;

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
                                Text('สรุปให้เห็นก่อน', style: AppText.heading(size: 14)),
                                const SizedBox(height: 12),
                                _SummaryRow(
                                  'ประสบการณ์',
                                  data.hasRunningExperience == true ? 'เคยซ้อม/แข่งวิ่ง' : 'ไม่เคย',
                                ),
                                _SummaryRow('เป้าหมาย', data.distanceGoal ?? data.healthGoal ?? '-'),
                                _SummaryRow('ระยะวิ่งไกลสุด', data.longestDistance),
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
                            () => ref.read(onboardingApiProvider).step4(_buildBody(data)),
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

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body(size: 13, color: AppColors.textSecondary)),
          Text(value, style: AppText.body(size: 13, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}
