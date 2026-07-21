/// A single day's "Daily Wellness Check-in" entry.
class WellnessEntry {
  int sleepQuality; // 0-10
  double sleepHours; // 0-12
  int muscleFatigue; // 0-10
  int musclePower; // 0-10
  int stressLevel; // 0-10

  WellnessEntry({
    this.sleepQuality = 7,
    this.sleepHours = 7,
    this.muscleFatigue = 3,
    this.musclePower = 7,
    this.stressLevel = 4,
  });
}
