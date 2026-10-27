/// En qué parte del día se saluda en el chat vacío sin nombre (F42): «Buen
/// día», «Buenas tardes» o «Buenas noches».
enum DayPart { morning, afternoon, evening }

/// La parte del día de [now], en su hora local: la mañana de 5 a 12, la tarde
/// de 12 a 20 y la noche de 20 a 5 —a las 2 de la mañana se dice «Buenas
/// noches», no «Buen día»—.
DayPart dayPartOf(DateTime now) => switch (now.hour) {
  >= 5 && < 12 => DayPart.morning,
  >= 12 && < 20 => DayPart.afternoon,
  _ => DayPart.evening,
};
