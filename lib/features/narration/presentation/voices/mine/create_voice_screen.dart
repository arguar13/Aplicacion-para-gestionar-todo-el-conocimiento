import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/util/format_file_size.dart';
import 'package:sinapsis/features/narration/data/voices/my_voices_service.dart';
import 'package:sinapsis/features/narration/domain/services/speech_clip_player.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_description.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_samples.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/offline_voice_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/my_voice_widgets.dart';
import 'package:sinapsis/features/narration/presentation/voices/mine/voice_cloud_sheet.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_texts.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre «Crear una voz» (F47, paso 4b) a pantalla completa, encima de todo.
Future<void> showCreateVoice(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const CreateVoiceScreen(),
      ),
    );

enum _Step { intro, design, name }

enum _Where { phone, cloud }

/// Crear una voz nueva describiéndola (F47, paso 4b), en tres pasos:
///
/// 1. **Qué es**, y dónde se crea: en el teléfono, gratis y por defecto,
///    mezclando voces de Kokoro; o en ElevenLabs, si la nube está prendida.
/// 2. **Cómo es**: una descripción en palabras, que se traduce a los
///    controles —el idioma y el acento, el género, la edad, el timbre, el
///    estilo y el ritmo—, o los controles a mano. Si la descripción nombra a
///    una persona real, la app lo dice y propone describir el estilo, y no
///    sigue. Se escucha una muestra —en el teléfono, la mezcla; en la nube,
///    tres propuestas, con su costo antes— y se ajusta.
/// 3. **El nombre y la cara**, y guardar.
class CreateVoiceScreen extends ConsumerStatefulWidget {
  const CreateVoiceScreen({super.key});

  @override
  ConsumerState<CreateVoiceScreen> createState() => _CreateVoiceScreenState();
}

class _CreateVoiceScreenState extends ConsumerState<CreateVoiceScreen> {
  var _step = _Step.intro;
  var _where = _Where.phone;
  final _description = TextEditingController();
  final _name = TextEditingController();

  /// De entrada, en el idioma de la app.
  late VoiceDesign _design = VoiceDesign(
    locale: Localizations.localeOf(context).languageCode == 'en'
        ? 'en-US'
        : 'es',
  );
  List<String> _understood = const [];
  String? _accentAsked;
  RealPersonFinding _realPerson = const RealPersonFinding([]);

  // La muestra.
  var _previewing = false;
  String? _previewError;
  var _playing = false;
  List<DesignedVoicePreview> _previews = const [];
  DesignedVoicePreview? _chosen;
  var _faceSeed = 0;
  var _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _description.addListener(_checkDescription);
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    _name.dispose();
    if (_playing) unawaited(ref.read(voiceSampleClipPlayerProvider).stop());
    super.dispose();
  }

  void _checkDescription() =>
      setState(() => _realPerson = checkRealPerson(_description.text));

  KokoroBlend get _blend => proposeBlend(_design);

  /// La descripción que va a ElevenLabs: la escrita, o la que arman los
  /// controles si no se escribió nada.
  String _cloudDescription(AppLocalizations l10n) {
    final written = _description.text.trim();
    if (written.isNotEmpty) return written;
    return [
      l10n.f47P4DescribedVoice(accentDisplayName(_design.locale)),
      if (_design.gender case final gender?) gender.label(l10n),
      if (_design.age case final age?) age.label(l10n),
      if (_design.timbre case final timbre?) timbre.label(l10n),
      if (_design.style case final style?) style.label(l10n),
    ].join(', ');
  }

  void _setDesign(VoiceDesign design) => setState(() {
    _design = design;
    // Lo que se escuchó era de la mezcla de antes.
    _previews = const [];
    _chosen = null;
  });

  void _interpret() {
    final described = interpretVoiceDescription(_description.text, _design);
    final locale = _where == _Where.phone
        ? described.design.locale
        : _cloudLocaleOf(described.design.locale, described.accent);
    _setDesign(described.design.copyWith(locale: locale));
    setState(() {
      _understood = described.understood;
      _accentAsked = described.accent;
    });
  }

  /// En la nube se puede pedir un acento con región: el que se nombró.
  static String _cloudLocaleOf(String locale, String? accent) {
    if (accent != null && cloudVoiceLocales.contains(accent)) return accent;
    if (cloudVoiceLocales.contains(locale)) return locale;
    // Kokoro dice `es` o `it` sin región: en la nube, el de su país.
    final withRegion = cloudVoiceLocales.where(
      (candidate) => accentLanguage(candidate) == accentLanguage(locale),
    );
    return withRegion.isEmpty ? cloudVoiceLocales.first : withRegion.first;
  }

  // --- Escuchar ------

  Future<File> _previewFile(String name) async => File(
    p.join((await ref.read(voicePreviewDirectoryProvider)()).path, name),
  );

  Future<void> _play(File file) async {
    final player = ref.read(voiceSampleClipPlayerProvider);
    setState(() => _playing = true);
    try {
      await player.play(FileSpeechClip(file.path));
    } on Object {
      // Un audio que no se pudo abrir: no suena.
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _listenOnPhone() async {
    final l10n = AppLocalizations.of(context)!;
    final text = voiceSampleText(accentLanguage(_design.locale));
    if (text == null) return;
    setState(() {
      _previewing = true;
      _previewError = null;
    });
    try {
      final file = await _previewFile('mezcla.wav');
      await ref
          .read(myVoicesServiceProvider)
          .previewOnPhone(blend: _blend, text: text, outputPath: file.path);
      if (!mounted) return;
      setState(() => _previewing = false);
      await _play(file);
    } on MyVoiceException {
      if (mounted) setState(() => _previewError = l10n.f47P4KokoroMissing);
    } on Object {
      if (mounted) setState(() => _previewError = l10n.f47P4PreviewFailed);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _designInCloud() async {
    final l10n = AppLocalizations.of(context)!;
    final text = _cloudPreviewText(l10n);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('create-cloud-cost'),
        title: Text(l10n.f47P4DesignCostTitle),
        content: Text(
          l10n.f47P4DesignCost(
            NumberFormat.decimalPattern(l10n.localeName).format(text.length),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.f47P4Cancel),
          ),
          FilledButton(
            key: const Key('create-cloud-approve'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.f47P4DesignApprove),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _previewing = true;
      _previewError = null;
      _previews = const [];
      _chosen = null;
    });
    try {
      final previews = await ref
          .read(myVoicesServiceProvider)
          .designInCloud(description: _cloudDescription(l10n), text: text);
      if (mounted) setState(() => _previews = previews);
    } on VoiceCloudException catch (error) {
      if (mounted) {
        setState(
          () => _previewError = voiceCloudFailureText(error.failure, l10n),
        );
      }
    } on Object {
      if (mounted) setState(() => _previewError = l10n.f47P4FailUnknown);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  /// El texto que dicen las propuestas de ElevenLabs: entre 100 y 1.000
  /// caracteres, en el idioma de la voz.
  String _cloudPreviewText(AppLocalizations l10n) {
    final sample = voiceSampleText(accentLanguage(_design.locale)) ?? '';
    final text = '$sample ${l10n.f47P4DesignPreviewText}'.trim();
    return text.length >= ElevenLabsFacts.designTextMin
        ? text
        : text.padRight(ElevenLabsFacts.designTextMin, '.');
  }

  Future<void> _playPreview(DesignedVoicePreview preview, int index) async {
    final file = await _previewFile('propuesta-$index.${preview.extension}')
      // Unos pocos KB: escribirlo de una vez no traba la pantalla.
      ..writeAsBytesSync(preview.audio, flush: true);
    if (!mounted) return;
    setState(() => _chosen = preview);
    await _play(file);
  }

  // --- Guardar ------

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final service = ref.read(myVoicesServiceProvider);
    try {
      final description = _description.text.trim();
      final voice = _where == _Where.phone
          ? await service.createOnPhone(
              name: _name.text,
              blend: _blend,
              design: _design,
              description: description,
              faceSeed: _faceSeed,
            )
          : await service.saveDesignedInCloud(
              name: _name.text,
              description: _cloudDescription(l10n),
              preview: _chosen!,
              design: _design,
              faceSeed: _faceSeed,
            );
      messenger.showAppSnackBar(
        AppSnackBar(content: Text(l10n.f47P4Saved(voice.name))),
      );
      navigator.pop();
    } on MyVoiceException catch (error) {
      if (mounted) {
        setState(
          () => _saveError = error.problem == MyVoiceProblem.noRoom
              ? l10n.f47P4NoRoom(kokoroSpeakerSlots)
              : l10n.f47P4KokoroMissing,
        );
      }
    } on VoiceCloudException catch (error) {
      if (mounted) {
        setState(() => _saveError = voiceCloudFailureText(error.failure, l10n));
      }
    } on Object {
      if (mounted) setState(() => _saveError = l10n.f47P4FailUnknown);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // --- La pantalla ------

  void _go(_Step step) => setState(() => _step = step);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.f47P4CreateTitle),
          leading: _step == _Step.intro
              ? const CloseButton()
              : BackButton(
                  onPressed: _saving
                      ? null
                      : () => _go(_Step.values[_step.index - 1]),
                ),
        ),
        body: SafeArea(
          // Una columna entera y no una lista perezosa: así el lector de
          // pantalla recorre todo, también lo de abajo.
          child: SingleChildScrollView(
            key: Key('create-voice-${_step.name}'),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: switch (_step) {
                _Step.intro => _intro(l10n),
                _Step.design => _designStep(l10n),
                _Step.name => _nameStep(l10n),
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _intro(AppLocalizations l10n) {
    final cloud = ref.watch(voiceCloudSettingsProvider);
    final available = ref.watch(myVoicesAvailableProvider);
    final kokoro =
        ref
            .watch(installedVoicePackagesProvider)
            .valueOrNull
            ?.contains(OfflineVoiceCatalog.kokoro.id) ??
        false;
    final ready = switch (_where) {
      _Where.phone => kokoro,
      _Where.cloud => cloud.ready,
    };
    return [
      IntroSection(
        icon: Icons.auto_awesome_outlined,
        title: l10n.f47P4WhatTitle,
        text: l10n.f47P4CreateWhat,
      ),
      IntroSection(
        icon: Icons.tune_rounded,
        title: l10n.f47P4HowTitle,
        text: l10n.f47P4CreateHow,
      ),
      IntroSection(
        icon: Icons.delete_outline_rounded,
        title: l10n.f47P4DeleteTitle,
        text: l10n.f47P4CreateDelete,
      ),
      const SizedBox(height: 8),
      Semantics(
        header: true,
        child: Text(
          l10n.f47P4WhereTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      RadioGroup<_Where>(
        groupValue: _where,
        onChanged: (value) => setState(() {
          _where = value ?? _Where.phone;
          _design = _design.copyWith(
            locale: _where == _Where.phone
                ? (OfflineVoiceCatalog.kokoroLocales.contains(_design.locale)
                      ? _design.locale
                      : 'es')
                : _cloudLocaleOf(_design.locale, null),
          );
        }),
        child: Column(
          children: [
            RadioListTile<_Where>(
              key: const Key('create-where-phone'),
              contentPadding: EdgeInsets.zero,
              value: _Where.phone,
              title: Text(l10n.f47P4WherePhoneFree),
              subtitle: Text(
                kokoro ? l10n.f47P4CreatePhoneHint : l10n.f47P4KokoroMissing,
              ),
            ),
            RadioListTile<_Where>(
              key: const Key('create-where-cloud'),
              contentPadding: EdgeInsets.zero,
              value: _Where.cloud,
              enabled: cloud.ready,
              title: Text(l10n.f47P4WhereCloud),
              subtitle: Text(
                cloud.ready ? l10n.f47P4CreateCloudHint : l10n.f47P4CloudNeeded,
              ),
            ),
          ],
        ),
      ),
      if (!cloud.ready)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: const Key('create-open-cloud'),
            onPressed: () => unawaited(showVoiceCloudSheet(context)),
            child: Text(l10n.f47P4CloudOpen),
          ),
        ),
      if (_where == _Where.phone && !kokoro && available)
        const _KokoroDownload(),
      if (!available) NoticeCard(text: l10n.f47P4OnlyAndroid),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('create-start'),
        onPressed: ready && available ? () => _go(_Step.design) : null,
        child: Text(l10n.f47P4Start),
      ),
    ];
  }

  List<Widget> _designStep(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final phone = _where == _Where.phone;
    final locales = phone
        ? OfflineVoiceCatalog.kokoroLocales
        : cloudVoiceLocales;
    final blocked = _realPerson.found;
    final ready = phone ? !blocked : !blocked && _chosen != null;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleSmall),
      ),
    );

    return [
      TextField(
        key: const Key('create-description'),
        controller: _description,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: l10n.f47P4DescribeLabel,
          hintText: l10n.f47P4DescribeHint,
          hintMaxLines: 3,
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: OutlinedButton(
          key: const Key('create-interpret'),
          onPressed: _description.text.trim().isEmpty || blocked
              ? null
              : _interpret,
          child: Text(l10n.f47P4Interpret),
        ),
      ),
      if (blocked)
        NoticeCard(
          key: const Key('create-real-person'),
          error: true,
          text: l10n.f47P4RealPerson(_realPerson.names.join(', ')),
        ),
      if (_understood.isNotEmpty)
        Text(
          l10n.f47P4Understood(_understood.join(', ')),
          key: const Key('create-understood'),
        ),
      if (_accentAsked case final accent? when phone)
        NoticeCard(
          key: const Key('create-accent-phone'),
          text: l10n.f47P4AccentOnPhone(accentDisplayName(accent)),
        ),
      heading(l10n.f47P4LanguageTitle),
      LocaleChips(
        locales: locales,
        selected: _design.locale,
        onSelected: (locale) => _setDesign(_design.copyWith(locale: locale)),
      ),
      heading(l10n.f47P3FilterGender),
      _Choices<VoiceGender>(
        values: VoiceGender.values,
        selected: _design.gender,
        label: (gender) => gender.label(l10n),
        keyPrefix: 'create-gender',
        onChanged: (gender) => _setDesign(
          _design.copyWith(gender: gender, clearGender: gender == null),
        ),
      ),
      heading(l10n.f47P3FilterAge),
      _Choices<VoiceAge>(
        values: VoiceAge.values,
        selected: _design.age,
        label: (age) => age.label(l10n),
        keyPrefix: 'create-age',
        onChanged: (age) =>
            _setDesign(_design.copyWith(age: age, clearAge: age == null)),
      ),
      heading(l10n.f47P3FilterTimbre),
      _Choices<VoiceTimbre>(
        values: VoiceTimbre.values,
        selected: _design.timbre,
        label: (timbre) => timbre.label(l10n),
        keyPrefix: 'create-timbre',
        onChanged: (timbre) => _setDesign(
          _design.copyWith(timbre: timbre, clearTimbre: timbre == null),
        ),
      ),
      heading(l10n.f47P3FilterStyle),
      _Choices<VoiceStyle>(
        values: VoiceStyle.values,
        selected: _design.style,
        label: (style) => style.label(l10n),
        keyPrefix: 'create-style',
        onChanged: (style) => _setDesign(
          _design.copyWith(style: style, clearStyle: style == null),
        ),
      ),
      if (phone) ...[
        heading(l10n.f47P4Pace(_design.pace.toStringAsFixed(2))),
        Slider(
          key: const Key('create-pace'),
          value: _design.pace,
          min: VoiceDesign.minPace,
          max: VoiceDesign.maxPace,
          divisions: 9,
          label: _design.pace.toStringAsFixed(2),
          semanticFormatterCallback: (value) =>
              l10n.f47P4Pace(value.toStringAsFixed(2)),
          onChanged: (value) => _setDesign(_design.copyWith(pace: value)),
        ),
        heading(l10n.f47P4MixTitle),
        Text(
          _mixLine(_blend),
          key: const Key('create-mix'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(l10n.f47P4MixHint, style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: 16),
      if (_previewing) ...[
        Semantics(liveRegion: true, child: Text(l10n.f47P4Generating)),
        const LinearProgressIndicator(),
      ] else
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (phone) ...[
              FilledButton.tonalIcon(
                key: const Key('create-listen'),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n.f47P4Listen),
                onPressed: blocked || _playing
                    ? null
                    : () => unawaited(_listenOnPhone()),
              ),
              OutlinedButton.icon(
                key: const Key('create-variant'),
                icon: const Icon(Icons.shuffle_rounded),
                label: Text(l10n.f47P4OtherVariant),
                onPressed: blocked
                    ? null
                    : () => _setDesign(
                        _design.copyWith(variant: _design.variant + 1),
                      ),
              ),
            ] else
              FilledButton.tonalIcon(
                key: const Key('create-design-cloud'),
                icon: const Icon(Icons.cloud_outlined),
                label: Text(l10n.f47P4DesignInCloud),
                onPressed: blocked ? null : () => unawaited(_designInCloud()),
              ),
          ],
        ),
      if (_previewError case final error?)
        NoticeCard(
          key: const Key('create-preview-error'),
          error: true,
          text: error,
        ),
      if (!phone && _previews.isNotEmpty) ...[
        heading(l10n.f47P4ProposalsTitle),
        for (final (index, preview) in _previews.indexed)
          RadioGroup<DesignedVoicePreview>(
            groupValue: _chosen,
            onChanged: (value) => setState(() => _chosen = value),
            child: RadioListTile<DesignedVoicePreview>(
              key: Key('create-proposal-$index'),
              contentPadding: EdgeInsets.zero,
              value: preview,
              title: Text(l10n.f47P4Proposal(index + 1)),
              secondary: IconButton(
                key: Key('create-proposal-play-$index'),
                tooltip: l10n.f47P3PlaySample,
                icon: const Icon(Icons.play_circle_outline_rounded),
                onPressed: _playing
                    ? null
                    : () => unawaited(_playPreview(preview, index)),
              ),
            ),
          ),
      ],
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('create-design-next'),
        onPressed: ready ? () => _go(_Step.name) : null,
        child: Text(l10n.f47P4Next),
      ),
    ];
  }

  String _mixLine(KokoroBlend blend) {
    final names = {
      for (final voice in OfflineVoiceCatalog.voices)
        if (voice.package == OfflineVoiceCatalog.kokoro)
          voice.speakerId: voice.name,
    };
    final percent = NumberFormat.percentPattern(
      AppLocalizations.of(context)!.localeName,
    );
    return [
      for (final part in blend.summary)
        [
          names[part.speakerId] ?? '#${part.speakerId}',
          percent.format(part.weight),
        ].join(' '),
    ].join(' · ');
  }

  List<Widget> _nameStep(AppLocalizations l10n) {
    return [
      TextField(
        key: const Key('create-name'),
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: l10n.f47P4VoiceName),
      ),
      const SizedBox(height: 16),
      FacePicker(
        faceKey: _faceSeed == 0 ? 'nueva' : 'nueva#$_faceSeed',
        name: _name.text,
        onNext: () => setState(() => _faceSeed++),
      ),
      const SizedBox(height: 16),
      Text(
        _where == _Where.phone
            ? l10n.f47P4SavePhoneHint
            : l10n.f47P4SaveCloudHint,
      ),
      if (_saveError case final error?)
        NoticeCard(
          key: const Key('create-save-error'),
          error: true,
          text: error,
        ),
      const SizedBox(height: 24),
      if (_saving)
        const LinearProgressIndicator()
      else
        FilledButton(
          key: const Key('create-save'),
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => unawaited(_save()),
          child: Text(l10n.f47P4Save),
        ),
    ];
  }
}

/// Elegir uno de [values], o ninguno («Sin definir»).
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.values,
    required this.selected,
    required this.label,
    required this.keyPrefix,
    required this.onChanged,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final String keyPrefix;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          key: Key('$keyPrefix-none'),
          label: Text(l10n.f47P4Undefined),
          selected: selected == null,
          onSelected: (_) => onChanged(null),
        ),
        for (final value in values)
          ChoiceChip(
            key: Key('$keyPrefix-${(value as Enum).name}'),
            label: Text(label(value)),
            selected: selected == value,
            onSelected: (_) => onChanged(value),
          ),
      ],
    );
  }
}

/// Bajar Kokoro, para crear en el teléfono: el paquete de siempre, con su
/// tamaño, solo si se toca.
class _KokoroDownload extends ConsumerWidget {
  const _KokoroDownload();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final actions = ref.watch(offlineVoiceActionsProvider);
    if (actions == null) return const SizedBox.shrink();
    const package = OfflineVoiceCatalog.kokoro;
    final state = ref.watch(offlineVoiceDownloadProvider(package.id));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: switch (state) {
        ModelDownloadRunning(:final progress) => Semantics(
          liveRegion: true,
          child: Text(
            l10n.f47P3Downloading((progress / 0.9 * 100).floor().clamp(0, 100)),
          ),
        ),
        _ => FilledButton.tonalIcon(
          key: const Key('create-download-kokoro'),
          icon: const Icon(Icons.download_rounded),
          label: Text(
            l10n.f47P4DownloadKokoro(
              formatFileSize(package.bytes, l10n.localeName),
            ),
          ),
          onPressed: () => actions.download(package),
        ),
      },
    );
  }
}
