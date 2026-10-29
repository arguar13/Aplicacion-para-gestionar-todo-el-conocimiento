import 'package:flutter/material.dart';
import 'package:sinapsis/features/creations/design/creation_icon_names.dart';

/// El juego de íconos de lo creado (F43): los de Material, cada uno con un
/// nombre estable para que la IA lo elija por escrito («"icon": "balance"»)
/// sin dibujar nada.
///
/// El nombre es lo que se guarda, no el ícono: si algún día se cambia el
/// dibujo de uno, los mazos ya hechos lo toman solos. Un nombre desconocido
/// —la IA inventó uno, o uno que una versión futura sacó— no rompe nada:
/// [resolve] devuelve el de reserva.
abstract final class CreationIcons {
  /// El de reserva: un destello, que va con cualquier tema.
  static const IconData fallback = Icons.auto_awesome;

  static const Map<String, IconData> byKey = {
    // Ideas y estudio.
    'lightbulb': Icons.lightbulb_outline,
    'book': Icons.menu_book,
    'stories': Icons.auto_stories,
    'school': Icons.school,
    'science': Icons.science,
    'biotech': Icons.biotech,
    'psychology': Icons.psychology,
    'history': Icons.history_edu,
    'quiz': Icons.quiz,
    'search': Icons.search,
    'visibility': Icons.visibility,
    'article': Icons.article,
    'edit': Icons.edit,
    'brush': Icons.brush,
    'palette': Icons.palette,
    'architecture': Icons.architecture,
    'calculate': Icons.calculate,
    'translate': Icons.translate,
    'puzzle': Icons.extension,
    'hub': Icons.hub,
    'layers': Icons.layers,
    'category': Icons.category,
    'checklist': Icons.checklist,
    // Datos y cambio.
    'insights': Icons.insights,
    'trending_up': Icons.trending_up,
    'trending_down': Icons.trending_down,
    'bar_chart': Icons.bar_chart,
    'pie_chart': Icons.pie_chart,
    'timeline': Icons.timeline,
    'target': Icons.track_changes,
    'speed': Icons.speed,
    'compare': Icons.compare_arrows,
    'sync': Icons.sync,
    'route': Icons.route,
    'hourglass': Icons.hourglass_empty,
    'schedule': Icons.schedule,
    'calendar': Icons.calendar_month,
    // Personas y sociedad.
    'person': Icons.person,
    'groups': Icons.groups,
    'family': Icons.family_restroom,
    'child': Icons.child_care,
    'handshake': Icons.handshake,
    'volunteer': Icons.volunteer_activism,
    'chat': Icons.chat_bubble_outline,
    'forum': Icons.forum,
    'campaign': Icons.campaign,
    'mail': Icons.mail_outline,
    'gavel': Icons.gavel,
    'balance': Icons.balance,
    'government': Icons.account_balance,
    'church': Icons.church,
    'medal': Icons.military_tech,
    'trophy': Icons.emoji_events,
    'flag': Icons.flag,
    'star': Icons.star_rounded,
    'favorite': Icons.favorite,
    'diamond': Icons.diamond,
    'castle': Icons.castle,
    'key': Icons.key,
    'lock': Icons.lock_outline,
    'shield': Icons.shield,
    // Mundo y naturaleza.
    'public': Icons.public,
    'map': Icons.map,
    'explore': Icons.explore,
    'place': Icons.place,
    'landscape': Icons.landscape,
    'park': Icons.park,
    'eco': Icons.eco,
    'water': Icons.water_drop,
    'fire': Icons.local_fire_department,
    'bolt': Icons.bolt,
    'sun': Icons.wb_sunny,
    'moon': Icons.dark_mode,
    'cloud': Icons.cloud,
    'recycle': Icons.recycling,
    'pets': Icons.pets,
    'agriculture': Icons.agriculture,
    'sailing': Icons.sailing,
    // Trabajo, técnica y vida diaria.
    'rocket': Icons.rocket_launch,
    'flight': Icons.flight,
    'build': Icons.build,
    'settings': Icons.settings,
    'code': Icons.code,
    'memory': Icons.memory,
    'computer': Icons.computer,
    'factory': Icons.factory,
    'store': Icons.storefront,
    'money': Icons.payments,
    'savings': Icons.savings,
    'health': Icons.health_and_safety,
    'medical': Icons.medical_services,
    'fitness': Icons.fitness_center,
    'restaurant': Icons.restaurant,
    'home': Icons.home_outlined,
    'city': Icons.location_city,
    'music': Icons.music_note,
    'movie': Icons.movie,
    'camera': Icons.photo_camera,
    // Señales.
    'check': Icons.check_circle_outline,
    'close': Icons.cancel_outlined,
    'warning': Icons.warning_amber,
    'info': Icons.info_outline,
    'help': Icons.help_outline,
    'quote': Icons.format_quote,
    'link': Icons.link,
    'sparkle': Icons.auto_awesome,
  };

  /// Nombres en castellano, o los de Material tal cual, que la IA a veces
  /// usa aunque se le pida otro: se aceptan para no tirar un buen ícono por
  /// un nombre.
  static const Map<String, String> _aliases = {
    'idea': 'lightbulb',
    'bombilla': 'lightbulb',
    'lightbulb_outline': 'lightbulb',
    'libro': 'book',
    'menu_book': 'book',
    'auto_stories': 'stories',
    'escuela': 'school',
    'ciencia': 'science',
    'mente': 'psychology',
    'historia': 'history',
    'history_edu': 'history',
    'buscar': 'search',
    'datos': 'insights',
    'grafico': 'bar_chart',
    'objetivo': 'target',
    'meta': 'target',
    'track_changes': 'target',
    'tiempo': 'schedule',
    'calendario': 'calendar',
    'persona': 'person',
    'personas': 'groups',
    'gente': 'groups',
    'familia': 'family',
    'justicia': 'balance',
    'ley': 'gavel',
    'gobierno': 'government',
    'account_balance': 'government',
    'iglesia': 'church',
    'mundo': 'public',
    'globe': 'public',
    'mapa': 'map',
    'lugar': 'place',
    'naturaleza': 'eco',
    'agua': 'water',
    'water_drop': 'water',
    'fuego': 'fire',
    'local_fire_department': 'fire',
    'energia': 'bolt',
    'sol': 'sun',
    'luna': 'moon',
    'cohete': 'rocket',
    'rocket_launch': 'rocket',
    'dinero': 'money',
    'payments': 'money',
    'salud': 'health',
    'musica': 'music',
    'advertencia': 'warning',
    'cita': 'quote',
    'format_quote': 'quote',
    'extension': 'puzzle',
    'auto_awesome': 'sparkle',
  };

  /// Los nombres que se le ofrecen a la IA, en orden.
  static List<String> get keys => creationIconNames;

  /// El nombre estable de [raw], o `null` si no es ninguno conocido. Tolera
  /// mayúsculas, espacios, guiones y tildes.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final key = _fold(
      raw.trim().toLowerCase(),
    ).replaceAll(RegExp(r'[\s\-]+'), '_').replaceAll(RegExp('[^a-z0-9_]'), '');
    if (byKey.containsKey(key)) return key;
    return _aliases[key];
  }

  /// El ícono de [key], o [fallback].
  static IconData resolve(String? key) => byKey[normalize(key)] ?? fallback;

  static String _fold(String text) => text
      .replaceAll(RegExp('[áàä]'), 'a')
      .replaceAll(RegExp('[éèë]'), 'e')
      .replaceAll(RegExp('[íìï]'), 'i')
      .replaceAll(RegExp('[óòö]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .replaceAll('ñ', 'n');
}
