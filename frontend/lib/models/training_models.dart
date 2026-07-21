/// The four trainable session types that can be placed on a day.
/// `race` and `restForced` are special auto-locked cell values used only
/// during the Race week and are not user-selectable from the tray.
enum SessionType { easy, long, tempo, vo2max, race, restForced }

/// The 5 sub-phases of the Intermediate 10K plan.
enum PlanPhase { base, build, peak, taper, race }

extension PlanPhaseX on PlanPhase {
  String get label {
    switch (this) {
      case PlanPhase.base:
        return 'Base';
      case PlanPhase.build:
        return 'Build';
      case PlanPhase.peak:
        return 'Peak';
      case PlanPhase.taper:
        return 'Taper (4.1)';
      case PlanPhase.race:
        return 'Race (4.2)';
    }
  }

  String get shortNumber {
    switch (this) {
      case PlanPhase.base:
        return '1';
      case PlanPhase.build:
        return '2';
      case PlanPhase.peak:
        return '3';
      case PlanPhase.taper:
        return '4.1';
      case PlanPhase.race:
        return '4.2';
    }
  }
}

/// Session types that count as "hard" for the adjacency rule: VO2Max,
/// Tempo and Long Run may never sit on two consecutive days.
const hardSessionTypes = {SessionType.vo2max, SessionType.tempo, SessionType.long};

class SessionMeta {
  final String icon;
  final String label;
  const SessionMeta(this.icon, this.label);
}

const sessionMeta = {
  SessionType.easy: SessionMeta('🏃', 'Easy Run'),
  SessionType.long: SessionMeta('🏞️', 'Long Run'),
  SessionType.tempo: SessionMeta('🔥', 'Tempo'),
  SessionType.vo2max: SessionMeta('⚡', 'VO2Max (Interval)'),
  SessionType.race: SessionMeta('🏁', 'Race Day'),
  SessionType.restForced: SessionMeta('', ''),
};

/// Weekly quota per session type for a given week (0 means "not used
/// this week").
class WeekCaps {
  final int easy;
  final int long;
  final int tempo;
  final int vo2max;
  const WeekCaps({this.easy = 0, this.long = 0, this.tempo = 0, this.vo2max = 0});

  int capFor(SessionType t) {
    switch (t) {
      case SessionType.easy:
        return easy;
      case SessionType.long:
        return long;
      case SessionType.tempo:
        return tempo;
      case SessionType.vo2max:
        return vo2max;
      default:
        return 0;
    }
  }

  int get total => easy + long + tempo + vo2max;

  Map<SessionType, int> get asMap => {
        SessionType.easy: easy,
        SessionType.vo2max: vo2max,
        SessionType.tempo: tempo,
        SessionType.long: long,
      };
}

String sessionDescription(SessionType type, PlanPhase phase) {
  switch (type) {
    case SessionType.easy:
      if (phase == PlanPhase.taper) return '4 กม./ครั้ง · โซนเบา';
      if (phase == PlanPhase.race) return '3–4 กม./ครั้ง · ผ่อนคลายก่อนแข่ง';
      return '30–40 นาที · Zone 2';
    case SessionType.long:
      return phase == PlanPhase.taper ? '6 กม. · ผ่อนความหนัก' : '6–8 กม. · เป้าหมาย Sub 1:40';
    case SessionType.tempo:
      return phase == PlanPhase.taper ? '10 นาที · คงความคม' : '10–20 นาที · จังหวะเทมโป';
    case SessionType.vo2max:
      return '200m x 4 เที่ยว · วิ่งเร็ว-พักฟื้น';
    default:
      return '';
  }
}
