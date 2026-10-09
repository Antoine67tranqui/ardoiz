/// Source de temps injectable (tests déterministes).
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();
