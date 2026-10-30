/// Lo que dice una voz en su muestra (F47, paso 3): una oración corta **en su
/// idioma** —no en el de la app—, porque una voz se elige por cómo suena en
/// lo que va a leer. `null` si no hay una oración para ese idioma: la muestra
/// no se ofrece, antes que oír una voz francesa diciendo algo en español.
String? voiceSampleText(String language) => _samples[language];

const _samples = {
  'es': 'Hola. Así sueno cuando leo tus documentos en voz alta.',
  'en': 'Hello. This is how I sound when I read your documents aloud.',
  'pt': 'Olá. É assim que eu soo quando leio os seus documentos em voz alta.',
  'fr': 'Bonjour. Voici ma voix quand je lis vos documents à voix haute.',
  'it': 'Ciao. Ecco come suono quando leggo ad alta voce i tuoi documenti.',
  'de': 'Hallo. So klinge ich, wenn ich deine Dokumente vorlese.',
  'ca': 'Hola. Així sono quan llegeixo els teus documents en veu alta.',
  'nl': 'Hallo. Zo klink ik als ik je documenten voorlees.',
  'ru': 'Здравствуйте. Так звучит мой голос, когда я читаю ваши документы.',
  'hi': 'नमस्ते। आपके दस्तावेज़ पढ़ते समय मेरी आवाज़ ऐसी लगती है।',
  'zh': '你好。这就是我朗读你的文档时的声音。',
  'ja': 'こんにちは。これが文書を読み上げるときの私の声です。',
};
